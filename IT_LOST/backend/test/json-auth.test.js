import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../src/app.js';
import { JsonAuthRepository } from '../src/auth/json-repository.js';
import { AuthService, DuplicateAccountError } from '../src/auth/auth-service.js';

const logger = { info() {}, warn() {}, error() {} };
const testAuthSecret = 'test-secret-with-at-least-thirty-two-bytes';

function memoryEmailSender() {
  const sent = [];
  return {
    sent,
    async sendVerificationCode({ to, name, code }) {
      sent.push({ to, name, code, purpose: 'verify' });
    },
    async sendPasswordResetCode({ to, name, code }) {
      sent.push({ to, name, code, purpose: 'reset' });
    },
    lastCode(email, purpose = 'verify') {
      const entry = [...sent].reverse().find((item) => item.to === email && item.purpose === purpose);
      return entry?.code;
    },
  };
}

function memoryRepository() {
  const users = new Map();
  const sessions = new Map();
  const emailCodes = [];
  let nextId = 1;
  return {
    users,
    sessions,
    emailCodes,
    async createUser({ name, email, passwordHash, verification }) {
      if ([...users.values()].some((user) => user.email === email)) {
        throw Object.assign(new Error('duplicate'), { code: 'EMAIL_EXISTS' });
      }
      const user = {
        id: nextId++,
        name,
        email,
        password_hash: passwordHash,
        is_verified: false,
        phone: '',
        facebook_link: '',
        instagram_link: '',
      };
      users.set(user.id, user);
      if (verification) {
        emailCodes.push({
          user_id: String(user.id),
          email,
          purpose: 'verify',
          code_hash: verification.codeHash,
          expires_at: verification.expiresAt.toISOString(),
          attempts: 0,
        });
      }
      return user;
    },
    async getUserByEmail(email) {
      const match = [...users.values()].find((user) => user.email === email);
      return match ? JSON.parse(JSON.stringify(match)) : null;
    },
    async storeEmailCode({ userId, email, purpose, codeHash, expiresAt }) {
      const filtered = emailCodes.filter((c) => !(c.user_id === String(userId) && c.purpose === purpose));
      emailCodes.length = 0;
      emailCodes.push(...filtered, {
        user_id: String(userId),
        email,
        purpose,
        code_hash: codeHash,
        expires_at: expiresAt.toISOString(),
        attempts: 0,
      });
      return true;
    },
    async verifyEmailCode({ email, codeHash, now = new Date() }) {
      const user = [...users.values()].find((u) => u.email === email);
      const index = emailCodes.findIndex((c) => c.email === email && c.purpose === 'verify');
      if (!user || index < 0) return { status: 'invalid' };
      const record = emailCodes[index];
      if (Date.parse(record.expires_at) <= now.getTime()) {
        emailCodes.splice(index, 1);
        return { status: 'expired' };
      }
      if (record.code_hash !== codeHash) {
        record.attempts += 1;
        if (record.attempts >= 5) {
          emailCodes.splice(index, 1);
          return { status: 'locked' };
        }
        return { status: 'invalid' };
      }
      user.is_verified = true;
      emailCodes.splice(index, 1);
      return { status: 'verified', user };
    },
    async clearLoginFailures() {},
    async loginLock() {
      return null;
    },
    async recordLoginFailure() {
      return null;
    },
    async updateProfile({ id, name, email, phone, facebookLink, instagramLink }) {
      if ([...users.values()].some((user) => user.email === email && user.id !== Number(id))) {
        throw Object.assign(new Error('duplicate'), { code: 'EMAIL_EXISTS' });
      }
      const user = users.get(Number(id));
      Object.assign(user, {
        name,
        email,
        phone,
        facebook_link: facebookLink,
        instagram_link: instagramLink,
      });
      return user;
    },
    async createSession({ userId, tokenHash, expiresAt }) {
      sessions.set(tokenHash.toString('hex'), { userId, expiresAt });
    },
    async findUserBySessionHash(hash) {
      const session = sessions.get(hash.toString('hex'));
      if (!session || session.expiresAt <= new Date()) return null;
      const user = users.get(session.userId);
      return user ? JSON.parse(JSON.stringify(user)) : null;
    },
    async deleteSession(hash) {
      sessions.delete(hash.toString('hex'));
    },
  };
}

test('supports multiple accounts and rejects duplicate normalized emails', async () => {
  const repository = memoryRepository();
  const emailSender = memoryEmailSender();
  const service = new AuthService({ repository, emailSender, authSecret: testAuthSecret });

  const first = await service.register({
    name: 'First User',
    email: 'FIRST@example.com',
    password: 'password123',
    confirmPassword: 'password123',
  });
  const second = await service.register({
    name: 'Second User',
    email: 'second@example.com',
    password: 'password456',
    confirmPassword: 'password456',
  });

  assert.match(first.message, /verification code/i);
  assert.equal(repository.users.size, 2);
  assert.equal(emailSender.sent.length, 2);
  assert.equal(emailSender.sent[0].to, 'first@example.com');
  assert.equal(emailSender.sent[1].to, 'second@example.com');

  await assert.rejects(
    service.register({
      name: 'Duplicate User',
      email: ' first@EXAMPLE.com ',
      password: 'password789',
      confirmPassword: 'password789',
    }),
    DuplicateAccountError,
  );
  assert.equal(repository.users.size, 2);

  await assert.rejects(
    service.register({
      name: 'Mismatch User',
      email: 'mismatch@example.com',
      password: 'password123',
      confirmPassword: 'different-password',
    }),
    /Passwords do not match/,
  );
});

test('authenticates, updates profile, and revokes a session', async () => {
  const repository = memoryRepository();
  const emailSender = memoryEmailSender();
  const service = new AuthService({ repository, emailSender, authSecret: testAuthSecret });

  await service.register({
    name: 'Profile User',
    email: 'profile@example.com',
    password: 'password123',
    confirmPassword: 'password123',
  });

  // Attempting to login before email verification must fail
  await assert.rejects(
    service.login({
      email: 'profile@example.com',
      password: 'password123',
    }),
    /Verify your email before signing in/,
  );

  // Complete email verification
  const code = emailSender.lastCode('profile@example.com');
  assert.ok(code);
  const verified = await service.verifyEmail({
    email: 'profile@example.com',
    code,
  });
  assert.equal(verified.user.email, 'profile@example.com');
  assert.ok(verified.token);

  // Login succeeds after verification
  const login = await service.login({
    email: ' PROFILE@example.com ',
    password: 'password123',
  });
  assert.equal(login.user.id, verified.user.id);
  assert.equal((await service.authenticate(login.token)).email, 'profile@example.com');

  const profile = await service.updateProfile(verified.user.id, {
    name: 'Updated User',
    email: 'updated@example.com',
    phone: '+639171234567',
    facebookLink: 'https://facebook.com/updated',
    instagramLink: 'https://instagram.com/updated',
  });
  assert.equal(profile.phone, '+639171234567');
  assert.equal(profile.facebookLink, 'https://facebook.com/updated');
  assert.equal(profile.instagramLink, 'https://instagram.com/updated');

  await service.logout(login.token);
  assert.equal(await service.authenticate(login.token), null);
});

test('HTTP API registers, rejects duplicates, signs in, and updates account details', async (context) => {
  const emailSender = memoryEmailSender();
  const service = new AuthService({
    repository: memoryRepository(),
    emailSender,
    authSecret: testAuthSecret,
  });
  const server = createServer(createApp({ service, logger }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(() => new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  }));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const post = (path, body, token) => fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });

  const createdResponse = await post('/auth/register', {
    name: 'API User',
    email: 'api@example.com',
    password: 'password123',
    confirmPassword: 'password123',
  });
  assert.equal(createdResponse.status, 201);
  const created = await createdResponse.json();
  assert.match(created.message, /verification code/i);

  const duplicate = await post('/auth/register', {
    name: 'API User',
    email: 'API@example.com',
    password: 'password123',
    confirmPassword: 'password123',
  });
  assert.equal(duplicate.status, 409);
  assert.match((await duplicate.json()).error, /already exists/i);

  // Unverified sign-in attempt returns 403
  const unverifiedLogin = await post('/auth/login', {
    email: 'api@example.com',
    password: 'password123',
  });
  assert.equal(unverifiedLogin.status, 403);

  // Verify email with the sent code
  const code = emailSender.lastCode('api@example.com');
  const verifyResponse = await post('/auth/verify-email', {
    email: 'api@example.com',
    code,
  });
  assert.equal(verifyResponse.status, 200);
  const session = await verifyResponse.json();
  assert.ok(session.token);
  assert.equal(session.user.email, 'api@example.com');

  const loggedIn = await post('/auth/login', {
    email: 'api@example.com',
    password: 'password123',
  });
  assert.equal(loggedIn.status, 200);

  const updated = await fetch(`${baseUrl}/auth/profile`, {
    method: 'PUT',
    headers: {
      authorization: `Bearer ${session.token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      name: 'Updated API User',
      email: 'api@example.com',
      phone: '09171234567',
      facebookLink: '',
      instagramLink: '',
    }),
  });
  assert.equal(updated.status, 200);
  assert.equal((await updated.json()).user.name, 'Updated API User');

  const logout = await post('/auth/logout', {}, session.token);
  assert.equal(logout.status, 204);
});

test('JSON repository persists independent accounts without storing plain credentials', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'campusfind-json-'));
  const filePath = join(directory, 'users.json');
  try {
    const repository = new JsonAuthRepository({ filePath });
    await repository.initialize();
    const emailSender = memoryEmailSender();
    const service = new AuthService({ repository, emailSender, authSecret: testAuthSecret });

    const first = await service.register({
      name: 'Local User',
      email: 'LOCAL@example.com',
      password: 'local-password-123',
      confirmPassword: 'local-password-123',
    });
    const second = await service.register({
      name: 'Second User',
      email: 'second@example.com',
      password: 'second-password-456',
      confirmPassword: 'second-password-456',
    });

    assert.match(first.message, /verification code/i);
    assert.match(second.message, /verification code/i);

    const code = emailSender.lastCode('local@example.com');
    await service.verifyEmail({ email: 'local@example.com', code });

    const stored = await readFile(filePath, 'utf8');
    const database = JSON.parse(stored);
    assert.equal(database.users.length, 2);
    assert.equal(stored.includes('local-password-123'), false);
    assert.match(database.users[0].password_hash, /^scrypt\$/);

    const reopenedRepository = new JsonAuthRepository({ filePath });
    await reopenedRepository.initialize();
    const reopenedService = new AuthService({
      repository: reopenedRepository,
      emailSender,
      authSecret: testAuthSecret,
    });
    const login = await reopenedService.login({
      email: 'local@example.com',
      password: 'local-password-123',
    });
    assert.equal(login.user.email, 'local@example.com');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('concurrent JSON registrations cannot create duplicate normalized emails', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'campusfind-json-race-'));
  try {
    const repository = new JsonAuthRepository({ filePath: join(directory, 'users.json') });
    await repository.initialize();
    const emailSender = memoryEmailSender();
    const service = new AuthService({ repository, emailSender, authSecret: testAuthSecret });
    const registrations = await Promise.allSettled([
      service.register({
        name: 'User One',
        email: 'same@example.com',
        password: 'password123',
        confirmPassword: 'password123',
      }),
      service.register({
        name: 'User Two',
        email: 'SAME@example.com',
        password: 'password456',
        confirmPassword: 'password456',
      }),
    ]);
    assert.equal(registrations.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal(registrations.filter((result) => result.status === 'rejected').length, 1);
    const database = JSON.parse(await readFile(join(directory, 'users.json'), 'utf8'));
    assert.equal(database.users.filter((u) => u.email === 'same@example.com').length, 1);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
