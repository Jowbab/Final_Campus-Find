import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MAX_CODE_ATTEMPTS = 5;
const LOGIN_WINDOW_MS = 15 * 60_000;
const LOGIN_MAX_ATTEMPTS = 5;
const LOGIN_LOCK_MS = 15 * 60_000;

export class JsonAuthRepository {
  constructor({ filePath = process.env.JSON_DB_FILE } = {}) {
    this.filePath = filePath
      ? resolve(filePath)
      : fileURLToPath(new URL('../../data/users.json', import.meta.url));
    this.writeQueue = Promise.resolve();
  }

  async initialize() {
    return this.#serialize(async () => {
      let contents;
      try {
        contents = await readFile(this.filePath, 'utf8');
      } catch (error) {
        if (error.code !== 'ENOENT') throw error;
        await this.#writeDatabase(emptyDatabase());
        return;
      }
      const needsMigration = JSON.parse(contents).version === 1;
      const database = this.#parseDatabase(contents);
      if (needsMigration) await this.#writeDatabase(database);
    });
  }

  async createUser({ name, email, passwordHash, verification }) {
    return this.#mutate((database) => {
      if (database.users.some((user) => user.email === email)) {
        throw Object.assign(new Error('Email already exists'), { code: 'EMAIL_EXISTS' });
      }
      const user = {
        id: database.nextUserId++,
        name,
        email,
        password_hash: passwordHash,
        is_verified: false,
        phone: '',
        facebook_link: '',
        instagram_link: '',
        created_at: new Date().toISOString(),
      };
      database.users.push(user);
      database.emailCodes.push(this.#codeRecord(user, 'verify', verification));
      return user;
    });
  }

  async getUserByEmail(email) {
    const database = await this.#readDatabase();
    return clone(database.users.find((user) => user.email === email) ?? null);
  }

  async getUserById(id) {
    const database = await this.#readDatabase();
    return clone(database.users.find((user) => String(user.id) === String(id)) ?? null);
  }

  async storeEmailCode({ userId, email, purpose, codeHash, expiresAt }) {
    return this.#mutate((database) => {
      const user = database.users.find((entry) => String(entry.id) === String(userId));
      if (!user || user.email !== email) return false;
      database.emailCodes = database.emailCodes.filter(
        (entry) => !(entry.user_id === String(user.id) && entry.purpose === purpose),
      );
      database.emailCodes.push(this.#codeRecord(user, purpose, { codeHash, expiresAt }));
      return true;
    });
  }

  async verifyEmailCode({ email, codeHash, now = new Date() }) {
    return this.#mutate((database) => {
      const user = database.users.find((entry) => entry.email === email);
      const index = database.emailCodes.findIndex(
        (entry) => entry.email === email && entry.purpose === 'verify',
      );
      if (!user || index < 0) return { status: 'invalid' };
      const record = database.emailCodes[index];
      if (Date.parse(record.expires_at) <= now.getTime()) {
        database.emailCodes.splice(index, 1);
        return { status: 'expired' };
      }
      if (record.attempts >= MAX_CODE_ATTEMPTS) {
        database.emailCodes.splice(index, 1);
        return { status: 'locked' };
      }
      if (!hashEquals(record.code_hash, codeHash)) {
        record.attempts += 1;
        if (record.attempts >= MAX_CODE_ATTEMPTS) {
          database.emailCodes.splice(index, 1);
          return { status: 'locked' };
        }
        return { status: 'invalid' };
      }
      user.is_verified = true;
      user.verified_at = now.toISOString();
      database.emailCodes.splice(index, 1);
      return { status: 'verified', user };
    });
  }

  async consumePasswordReset({ email, codeHash, passwordHash, now = new Date() }) {
    return this.#mutate((database) => {
      const user = database.users.find((entry) => entry.email === email && entry.is_verified);
      const index = database.emailCodes.findIndex(
        (entry) => entry.email === email && entry.purpose === 'reset',
      );
      if (!user || index < 0) return { status: 'invalid' };
      const record = database.emailCodes[index];
      if (Date.parse(record.expires_at) <= now.getTime()) {
        database.emailCodes.splice(index, 1);
        return { status: 'expired' };
      }
      if (record.attempts >= MAX_CODE_ATTEMPTS) {
        database.emailCodes.splice(index, 1);
        return { status: 'locked' };
      }
      if (!hashEquals(record.code_hash, codeHash)) {
        record.attempts += 1;
        if (record.attempts >= MAX_CODE_ATTEMPTS) {
          database.emailCodes.splice(index, 1);
          return { status: 'locked' };
        }
        return { status: 'invalid' };
      }
      user.password_hash = passwordHash;
      user.password_updated_at = now.toISOString();
      database.emailCodes = database.emailCodes.filter(
        (entry) => !(entry.user_id === String(user.id) && entry.purpose === 'reset'),
      );
      database.sessions = database.sessions.filter(
        (session) => session.user_id !== String(user.id),
      );
      return { status: 'reset' };
    });
  }

  async loginLock(email, now = new Date()) {
    const database = await this.#readDatabase();
    const attempt = database.loginAttempts.find((entry) => entry.email === email);
    if (!attempt) return null;
    if (attempt.locked_until && Date.parse(attempt.locked_until) > now.getTime()) {
      return new Date(attempt.locked_until);
    }
    if (now.getTime() - Date.parse(attempt.window_started_at) >= LOGIN_WINDOW_MS) return null;
    return null;
  }

  async recordLoginFailure(email, now = new Date()) {
    return this.#mutate((database) => {
      let attempt = database.loginAttempts.find((entry) => entry.email === email);
      if (!attempt || now.getTime() - Date.parse(attempt.window_started_at) >= LOGIN_WINDOW_MS) {
        database.loginAttempts = database.loginAttempts.filter((entry) => entry.email !== email);
        attempt = { email, count: 0, window_started_at: now.toISOString(), locked_until: null };
        database.loginAttempts.push(attempt);
      }
      attempt.count += 1;
      if (attempt.count >= LOGIN_MAX_ATTEMPTS) {
        attempt.locked_until = new Date(now.getTime() + LOGIN_LOCK_MS).toISOString();
      }
      return attempt.locked_until ? new Date(attempt.locked_until) : null;
    });
  }

  async clearLoginFailures(email) {
    return this.#mutate((database) => {
      database.loginAttempts = database.loginAttempts.filter((entry) => entry.email !== email);
    });
  }

  async updateProfile({ id, name, email, phone, facebookLink, instagramLink }) {
    return this.#mutate((database) => {
      const user = database.users.find((entry) => String(entry.id) === String(id));
      if (!user) return null;
      if (database.users.some((entry) => entry.email === email && entry.id !== user.id)) {
        throw Object.assign(new Error('Email already exists'), { code: 'EMAIL_EXISTS' });
      }
      if (email !== user.email) {
        throw Object.assign(new Error('Email changes require verification.'), { code: 'EMAIL_CHANGE_REQUIRES_VERIFICATION' });
      }
      Object.assign(user, {
        name,
        phone,
        facebook_link: facebookLink,
        instagram_link: instagramLink,
      });
      return user;
    });
  }

  async createSession({ userId, tokenHash, expiresAt }) {
    return this.#mutate((database) => {
      database.sessions.push({
        user_id: String(userId),
        token_hash: tokenHash.toString('hex'),
        expires_at: new Date(expiresAt).toISOString(),
      });
    });
  }

  async findUserBySessionHash(tokenHash) {
    const database = await this.#readDatabase();
    const hash = tokenHash.toString('hex');
    const session = database.sessions.find(
      (entry) => entry.token_hash === hash && Date.parse(entry.expires_at) > Date.now(),
    );
    if (!session) return null;
    return clone(database.users.find(
      (user) => String(user.id) === session.user_id && user.is_verified,
    ) ?? null);
  }

  async deleteSession(tokenHash) {
    const hash = tokenHash.toString('hex');
    return this.#mutate((database) => {
      database.sessions = database.sessions.filter((session) => session.token_hash !== hash);
    });
  }

  async deleteExpiredSessions() {
    return this.#mutate((database) => {
      database.sessions = database.sessions.filter(
        (session) => Date.parse(session.expires_at) > Date.now(),
      );
    });
  }

  #codeRecord(user, purpose, { codeHash, expiresAt }) {
    return {
      user_id: String(user.id),
      email: user.email,
      purpose,
      code_hash: codeHash,
      expires_at: new Date(expiresAt).toISOString(),
      attempts: 0,
      created_at: new Date().toISOString(),
    };
  }

  async #mutate(mutator) {
    return this.#serialize(async () => {
      const database = await this.#readDatabase();
      const result = await mutator(database);
      await this.#writeDatabase(database);
      return clone(result);
    });
  }

  async #serialize(operation) {
    const pending = this.writeQueue.then(operation, operation);
    this.writeQueue = pending.then(() => undefined, () => undefined);
    return pending;
  }

  async #readDatabase() {
    let contents;
    try {
      contents = await readFile(this.filePath, 'utf8');
    } catch (error) {
      if (error.code === 'ENOENT') return emptyDatabase();
      throw error;
    }
    return this.#parseDatabase(contents);
  }

  #parseDatabase(contents) {
    let database;
    try {
      database = JSON.parse(contents);
    } catch {
      throw new Error(`Local JSON database is not valid JSON: ${this.filePath}`);
    }
    if (database?.version === 1) {
      database.version = 2;
      database.emailCodes = [];
      database.loginAttempts = [];
      for (const user of database.users ?? []) user.is_verified ??= true;
    }
    if (
      database?.version !== 2 ||
      !Number.isSafeInteger(database.nextUserId) ||
      !Array.isArray(database.users) ||
      !Array.isArray(database.sessions) ||
      !Array.isArray(database.emailCodes) ||
      !Array.isArray(database.loginAttempts)
    ) {
      throw new Error(`Local JSON database has an unsupported structure: ${this.filePath}`);
    }
    return database;
  }

  async #writeDatabase(database) {
    await mkdir(dirname(this.filePath), { recursive: true });
    const temporaryPath = `${this.filePath}.${process.pid}.${randomBytes(6).toString('hex')}.tmp`;
    try {
      await writeFile(temporaryPath, `${JSON.stringify(database, null, 2)}\n`, {
        encoding: 'utf8',
        mode: 0o600,
      });
      await rename(temporaryPath, this.filePath);
    } catch (error) {
      await unlink(temporaryPath).catch(() => {});
      throw error;
    }
  }
}

function emptyDatabase() {
  return {
    version: 2,
    nextUserId: 1,
    users: [],
    sessions: [],
    emailCodes: [],
    loginAttempts: [],
  };
}

function hashEquals(storedHex, candidate) {
  const stored = Buffer.from(storedHex, 'hex');
  const supplied = Buffer.from(candidate, 'hex');
  return stored.length === supplied.length && timingSafeEqual(stored, supplied);
}

function clone(value) {
  return value == null ? value : structuredClone(value);
}
