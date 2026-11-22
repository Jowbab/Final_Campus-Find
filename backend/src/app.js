import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import { AuthError } from './auth/auth-service.js';

const SESSION_COOKIE = 'campusfind_session';
const SESSION_MAX_AGE_SECONDS = 30 * 24 * 60 * 60;

export function createApp({ service, corsOrigins = [], trustProxy = false, logger = console }) {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', trustProxy);

  const allowedOrigins = new Set(corsOrigins);
  app.use(cors({
    origin(origin, callback) {
      const localDevelopmentOrigin = process.env.NODE_ENV !== 'production' &&
        /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin ?? '');
      callback(null, !origin || allowedOrigins.has(origin) || localDevelopmentOrigin);
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    optionsSuccessStatus: 204,
  }));
  app.use(express.json({ limit: '16kb' }));

  const authLimit = rateLimit({
    windowMs: 15 * 60_000,
    limit: 30,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: (_req, res) => res.status(429).json({ error: 'Please wait before trying again.' }),
  });
  const loginLimit = rateLimit({
    windowMs: 15 * 60_000,
    limit: 10,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    handler: (_req, res) => res.status(429).json({ error: 'Too many sign-in attempts. Try again later.' }),
  });
  const auth = express.Router();
  auth.use(authLimit);

  auth.post('/register', async (req, res, next) => {
    try {
      const result = await service.register(req.body ?? {});
      return res.status(201).json(result);
    } catch (error) {
      return next(error);
    }
  });

  auth.post('/verify-email', async (req, res, next) => {
    try {
      const session = await service.verifyEmail(req.body ?? {});
      return sendSession(req, res, session, 200);
    } catch (error) {
      return next(error);
    }
  });

  auth.post('/resend-verification', async (req, res, next) => {
    try {
      return res.status(202).json(await service.resendVerification(req.body?.email));
    } catch (error) {
      return next(error);
    }
  });

  auth.post('/login', loginLimit, async (req, res, next) => {
    try {
      const session = await service.login(req.body ?? {});
      return sendSession(req, res, session, 200);
    } catch (error) {
      return next(error);
    }
  });

  auth.post('/password-reset/request', async (req, res, next) => {
    try {
      return res.status(202).json(await service.requestPasswordReset(req.body?.email));
    } catch (error) {
      return next(error);
    }
  });

  auth.post('/password-reset/confirm', async (req, res, next) => {
    try {
      return res.status(200).json(await service.resetPassword(req.body ?? {}));
    } catch (error) {
      return next(error);
    }
  });

  const requireSession = async (req, res, next) => {
    try {
      const authorization = req.get('authorization') ?? '';
      const match = /^Bearer ([A-Za-z0-9_-]+)$/.exec(authorization);
      const token = match?.[1] ?? cookieValue(req, SESSION_COOKIE);
      const user = token ? await service.authenticate(token) : null;
      if (!user) return res.status(401).json({ error: 'Authentication required.' });
      req.sessionUser = user;
      req.sessionToken = token;
      return next();
    } catch (error) {
      return next(error);
    }
  };

  auth.get('/me', requireSession, (req, res) => res.status(200).json({ user: req.sessionUser }));
  auth.put('/profile', requireSession, async (req, res, next) => {
    try {
      const user = await service.updateProfile(req.sessionUser.id, req.body ?? {});
      return res.status(200).json({ user });
    } catch (error) {
      return next(error);
    }
  });
  auth.post('/logout', requireSession, async (req, res, next) => {
    try {
      await service.logout(req.sessionToken);
      if (req.get('origin')) clearSessionCookie(res);
      return res.sendStatus(204);
    } catch (error) {
      return next(error);
    }
  });

  app.use('/auth', auth);
  app.get('/health', (_req, res) => res.status(200).json({ ok: true }));
  app.use((_req, res) => res.status(404).json({ error: 'Not found.' }));
  app.use((error, _req, res, _next) => {
    if (error instanceof AuthError) {
      return res.status(error.statusCode).json({ error: error.message });
    }
    logger.error({ event: 'request_failed', code: error.code ?? 'unknown' });
    return res.status(500).json({ error: 'Unable to complete your request.' });
  });

  return app;
}

function sendSession(req, res, session, statusCode) {
  if (req.get('origin')) {
    setSessionCookie(res, session.token);
    return res.status(statusCode).json({ user: session.user });
  }
  return res.status(statusCode).json(session);
}

function setSessionCookie(res, token) {
  const secure = process.env.NODE_ENV === 'production' ? '; Secure' : '';
  res.setHeader(
    'Set-Cookie',
    `${SESSION_COOKIE}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_MAX_AGE_SECONDS}${secure}`,
  );
}

function clearSessionCookie(res) {
  const secure = process.env.NODE_ENV === 'production' ? '; Secure' : '';
  res.setHeader(
    'Set-Cookie',
    `${SESSION_COOKIE}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0${secure}`,
  );
}

function cookieValue(req, name) {
  const header = req.get('cookie') ?? '';
  for (const part of header.split(';')) {
    const [key, ...valueParts] = part.trim().split('=');
    if (key === name) return valueParts.join('=');
  }
  return null;
}
