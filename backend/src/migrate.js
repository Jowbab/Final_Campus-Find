import 'dotenv/config';
import { JsonAuthRepository } from './auth/json-repository.js';

const repository = new JsonAuthRepository();
await repository.initialize();
console.info(`Local JSON database is ready: ${repository.filePath}`);
