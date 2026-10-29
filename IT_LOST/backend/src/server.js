import 'dotenv/config';
import { JsonAuthRepository } from './auth/json-repository.js';
import { AuthService } from './auth/auth-service.js';
import { createEmailSender } from './email/email-sender.js';
import { createApp } from './app.js';

const repository = new JsonAuthRepository();
await repository.initialize();
const service = new AuthService({ repository, emailSender: createEmailSender() });
await repository.deleteExpiredSessions();
const app = createApp({
  service,
  corsOrigins: (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
  trustProxy: process.env.TRUST_PROXY === '1' ? 1 : false,
});

const port = Number(process.env.PORT ?? 3000);
const server = app.listen(port, '0.0.0.0', () => {
  console.info({ event: 'server_started', port, storage: repository.filePath });
});

function shutdown() {
  server.close(() => process.exit(0));
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
