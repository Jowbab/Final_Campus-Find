import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const SCRYPT_COST = 32_768;
const SCRYPT_BLOCK_SIZE = 8;
const SCRYPT_PARALLELIZATION = 1;
const SESSION_TTL_DAYS = 30;
const EMAIL_CODE_TTL_MS = 15 * 60_000;

export class AuthError extends Error {
  constructor(message, statusCode) {
    super(message);
    this.statusCode = statusCode;
  }
}

export class DuplicateAccountError extends AuthError {
  constructor() {
    super('An account with this email already exists.', 409);
  }
}

export class InvalidCredentialsError extends AuthError {
  constructor() {
    super('Email or password is incorrect.', 401);
  }
}

export class AuthService {
  constructor({ repository, emailSender, authSecret = process.env.AUTH_TOKEN_SECRET, clock = () => new Date() }) {
    if (!authSecret || Buffer.byteLength(authSecret) < 32) {
      throw new Error('AUTH_TOKEN_SECRET must contain at least 32 bytes');
    }
    this.repository = repository;
    this.emailSender = emailSender;
    this.authSecret = authSecret;
    this.clock = clock;
  }

  async register({ name, email, password, confirmPassword }) {
    const profile = validateRegistration({ name, email, password, confirmPassword });
    const verification = this.#newEmailCode(profile.email, 'verify');
    let user;
    try {
      user = await this.repository.createUser({
        ...profile,
        passwordHash: await hashPassword(password),
        verification,
      });
    } catch (error) {
      if (error.code === 'EMAIL_EXISTS') throw new DuplicateAccountError();
      throw error;
    }
    await this.#sendEmailCode('verification', user, verification.code);
    return { message: 'Check your email for a verification code.' };
  }

  async verifyEmail({ email, code }) {
    const normalizedEmail = requireEmail(email);
    validateCode(code, 'verification');
    const result = await this.repository.verifyEmailCode({
      email: normalizedEmail,
      codeHash: this.#hashEmailCode(normalizedEmail, 'verify', code),
      now: this.clock(),
    });
    this.#assertCodeResult(result, 'verification');
    await this.repository.clearLoginFailures(normalizedEmail);
    return this.#createSession(result.user);
  }

  async resendVerification(email) {
    const normalizedEmail = requireEmail(email);
    const user = await this.repository.getUserByEmail(normalizedEmail);
    if (user && !user.is_verified) {
      const verification = this.#newEmailCode(normalizedEmail, 'verify');
      await this.repository.storeEmailCode({
        userId: user.id,
        email: normalizedEmail,
        purpose: 'verify',
        codeHash: verification.codeHash,
        expiresAt: verification.expiresAt,
      });
      await this.#sendEmailCode('verification', user, verification.code);
    }
    return { message: 'If this address needs verification, a code has been sent.' };
  }

  async login({ email, password }) {
    if (typeof email !== 'string' || typeof password !== 'string') {
      throw new InvalidCredentialsError();
    }
    const normalizedEmail = normalizeEmail(email);
    const lockUntil = await this.repository.loginLock(normalizedEmail, this.clock());
    if (lockUntil) throw new AuthError('Too many sign-in attempts. Try again later.', 429);

    const user = await this.repository.getUserByEmail(normalizedEmail);
    if (!user || !(await verifyPassword(password, user.password_hash))) {
      const blockedUntil = await this.repository.recordLoginFailure(normalizedEmail, this.clock());
      if (blockedUntil) throw new AuthError('Too many sign-in attempts. Try again later.', 429);
      throw new InvalidCredentialsError();
    }
    if (!user.is_verified) throw new AuthError('Verify your email before signing in.', 403);
    await this.repository.clearLoginFailures(normalizedEmail);
    return this.#createSession(user);
  }

  async requestPasswordReset(email) {
    const normalizedEmail = requireEmail(email);
    const user = await this.repository.getUserByEmail(normalizedEmail);
    if (user?.is_verified) {
      const reset = this.#newEmailCode(normalizedEmail, 'reset');
      await this.repository.storeEmailCode({
        userId: user.id,
        email: normalizedEmail,
        purpose: 'reset',
        codeHash: reset.codeHash,
        expiresAt: reset.expiresAt,
      });
      await this.#sendEmailCode('password reset', user, reset.code);
    }
    return { message: 'If an account exists for this address, a reset code has been sent.' };
  }

  async resetPassword({ email, code, password, confirmPassword }) {
    const normalizedEmail = requireEmail(email);
    validatePassword(password, confirmPassword);
    validateCode(code, 'password reset');
    const result = await this.repository.consumePasswordReset({
      email: normalizedEmail,
      codeHash: this.#hashEmailCode(normalizedEmail, 'reset', code),
      passwordHash: await hashPassword(password),
      now: this.clock(),
    });
    this.#assertCodeResult(result, 'password reset');
    await this.repository.clearLoginFailures(normalizedEmail);
    return { message: 'Password reset. Sign in with your new password.' };
  }

  async authenticate(token) {
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{40,}$/.test(token)) return null;
    const tokenHash = createHash('sha256').update(token).digest();
    const row = await this.repository.findUserBySessionHash(tokenHash);
    return row ? toPublicUser(row) : null;
  }

  async logout(token) {
    if (typeof token !== 'string') return;
    await this.repository.deleteSession(createHash('sha256').update(token).digest());
  }

  async updateProfile(userId, input) {
    const profile = validateProfile(input);
    let user;
    try {
      user = await this.repository.updateProfile({ id: userId, ...profile });
    } catch (error) {
      if (error.code === 'EMAIL_EXISTS') throw new DuplicateAccountError();
      if (error.code === 'EMAIL_CHANGE_REQUIRES_VERIFICATION') {
        throw new AuthError('Changing your email requires verification.', 409);
      }
      throw error;
    }
    if (!user) throw new AuthError('Account not found.', 404);
    return toPublicUser(user);
  }

  async #createSession(user) {
    const token = randomBytes(32).toString('base64url');
    const tokenHash = createHash('sha256').update(token).digest();
    const expiresAt = new Date(
      this.clock().getTime() + SESSION_TTL_DAYS * 24 * 60 * 60 * 1000,
    );
    await this.repository.createSession({ userId: user.id, tokenHash, expiresAt });
    return { token, user: toPublicUser(user) };
  }

  #newEmailCode(email, purpose) {
    const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
    return {
      code,
      codeHash: this.#hashEmailCode(email, purpose, code),
      expiresAt: new Date(this.clock().getTime() + EMAIL_CODE_TTL_MS),
    };
  }

  #hashEmailCode(email, purpose, code) {
    return createHmac('sha256', this.authSecret)
      .update(`${purpose}:${email}:${code}`)
      .digest('hex');
  }

  #assertCodeResult(result, purpose) {
    if (result.status === 'verified' || result.status === 'reset') return;
    if (result.status === 'locked') {
      throw new AuthError(`Too many ${purpose} attempts. Request a new code.`, 429);
    }
    throw new AuthError(`Invalid or expired ${purpose} code.`, 400);
  }

  async #sendEmailCode(purpose, user, code) {
    if (!this.emailSender) {
      throw new AuthError('Email delivery is not configured on the server.', 503);
    }
    try {
      if (purpose === 'verification') {
        await this.emailSender.sendVerificationCode({ to: user.email, name: user.name, code });
      } else {
        await this.emailSender.sendPasswordResetCode({ to: user.email, name: user.name, code });
      }
    } catch {
      throw new AuthError('Could not send email. Please try again later.', 503);
    }
  }
}

export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

function requireEmail(email) {
  if (typeof email !== 'string' || !isValidEmail(email)) {
    throw new AuthError('Enter a valid email address.', 400);
  }
  return normalizeEmail(email);
}

function validateRegistration({ name, email, password, confirmPassword }) {
  if (typeof name !== 'string' || name.trim().length < 2 || name.trim().length > 100) {
    throw new AuthError('Enter a name between 2 and 100 characters.', 400);
  }
  const normalizedEmail = requireEmail(email);
  validatePassword(password, confirmPassword);
  return { name: name.trim(), email: normalizedEmail };
}

function validatePassword(password, confirmPassword) {
  if (typeof password !== 'string' || password.length < 8 || password.length > 256) {
    throw new AuthError('Password must be between 8 and 256 characters.', 400);
  }
  if (typeof confirmPassword !== 'string' || password !== confirmPassword) {
    throw new AuthError('Passwords do not match.', 400);
  }
}

function validateCode(code, purpose) {
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) {
    throw new AuthError(`Invalid or expired ${purpose} code.`, 400);
  }
}

function validateProfile({ name, email, phone = '', facebookLink = '', instagramLink = '' }) {
  if (typeof name !== 'string' || name.trim().length < 2 || name.trim().length > 100) {
    throw new AuthError('Enter a name between 2 and 100 characters.', 400);
  }
  const normalizedEmail = requireEmail(email);
  for (const [label, value, maxLength] of [
    ['Phone number', phone, 32],
    ['Facebook link', facebookLink, 2048],
    ['Instagram link', instagramLink, 2048],
  ]) {
    if (typeof value !== 'string' || value.length > maxLength) {
      throw new AuthError(`${label} is invalid.`, 400);
    }
  }
  return {
    name: name.trim(),
    email: normalizedEmail,
    phone: phone.trim(),
    facebookLink: validateOptionalLink(facebookLink, 'Facebook link'),
    instagramLink: validateOptionalLink(instagramLink, 'Instagram link'),
  };
}

function isValidEmail(email) {
  return email.trim().length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

function validateOptionalLink(value, label) {
  const link = value.trim();
  if (link.length === 0) return '';
  let parsed;
  try {
    parsed = new URL(link);
  } catch {
    throw new AuthError(`${label} must be a full https URL.`, 400);
  }
  if (parsed.protocol !== 'https:' || !parsed.hostname) {
    throw new AuthError(`${label} must be a full https URL.`, 400);
  }
  return link;
}

async function hashPassword(password) {
  const salt = randomBytes(16);
  const derivedKey = await scrypt(password, salt, 64, {
    N: SCRYPT_COST,
    r: SCRYPT_BLOCK_SIZE,
    p: SCRYPT_PARALLELIZATION,
    maxmem: 64 * 1024 * 1024,
  });
  return `scrypt$${SCRYPT_COST}$${salt.toString('base64url')}$${derivedKey.toString('base64url')}`;
}

async function verifyPassword(password, storedHash) {
  if (typeof storedHash !== 'string' || typeof password !== 'string') return false;
  const [algorithm, costText, saltText, keyText] = storedHash.split('$');
  if (algorithm !== 'scrypt' || Number(costText) !== SCRYPT_COST || !saltText || !keyText) {
    return false;
  }
  try {
    const salt = Buffer.from(saltText, 'base64url');
    const expected = Buffer.from(keyText, 'base64url');
    const actual = await scrypt(password, salt, expected.length, {
      N: SCRYPT_COST,
      r: SCRYPT_BLOCK_SIZE,
      p: SCRYPT_PARALLELIZATION,
      maxmem: 64 * 1024 * 1024,
    });
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function toPublicUser(user) {
  return {
    id: String(user.id),
    name: user.name,
    email: user.email,
    isVerified: Boolean(user.is_verified),
    phone: user.phone ?? '',
    facebookLink: user.facebook_link ?? user.facebookLink ?? '',
    instagramLink: user.instagram_link ?? user.instagramLink ?? '',
  };
}
