import { randomBytes } from 'node:crypto';
import { access, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const envPath = fileURLToPath(new URL('../.env', import.meta.url));

try {
  await access(envPath);
} catch (error) {
  if (error.code !== 'ENOENT') throw error;

  const template = await readFile(new URL('../.env.example', import.meta.url), 'utf8');
  const localConfig = template.replace(
    /^AUTH_TOKEN_SECRET=.*$/m,
    `AUTH_TOKEN_SECRET=${randomBytes(32).toString('base64url')}`,
  );

  try {
    await writeFile(envPath, localConfig, { encoding: 'utf8', flag: 'wx' });
    console.info('Created backend/.env with a random local development secret.');
  } catch (writeError) {
    if (writeError.code !== 'EEXIST') throw writeError;
  }
}
