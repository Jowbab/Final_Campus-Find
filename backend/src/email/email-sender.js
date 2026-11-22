import nodemailer from 'nodemailer';

export function createEmailSender(environment = process.env, logger = console) {
  const { SMTP_HOST, SMTP_USER, SMTP_PASSWORD, SMTP_FROM } = environment;
  if (!SMTP_HOST || !SMTP_USER || !SMTP_PASSWORD || !SMTP_FROM) {
    if (environment.NODE_ENV === 'production') return null;

    return {
      async sendVerificationCode({ to, name, code }) {
        logger.info?.(`[CampusFind Dev Email] Verification code for ${to} (${name}): ${code}`);
      },
      async sendPasswordResetCode({ to, name, code }) {
        logger.info?.(`[CampusFind Dev Email] Password reset code for ${to} (${name}): ${code}`);
      },
    };
  }

  const port = Number(environment.SMTP_PORT ?? 587);
  const transport = nodemailer.createTransport({
    host: SMTP_HOST,
    port,
    secure: environment.SMTP_SECURE === 'true' || port === 465,
    auth: { user: SMTP_USER, pass: SMTP_PASSWORD },
    connectionTimeout: 10_000,
    greetingTimeout: 10_000,
    socketTimeout: 15_000,
  });

  return {
    async sendVerificationCode({ to, name, code }) {
      await transport.sendMail({
        from: SMTP_FROM,
        to,
        subject: 'Verify your CampusFind email',
        text: `Hi ${name},\n\nYour CampusFind verification code is ${code}. It expires in 15 minutes.\n\nIf you did not create this account, you can ignore this email.`,
      });
    },
    async sendPasswordResetCode({ to, name, code }) {
      await transport.sendMail({
        from: SMTP_FROM,
        to,
        subject: 'Reset your CampusFind password',
        text: `Hi ${name},\n\nYour CampusFind password reset code is ${code}. It expires in 15 minutes.\n\nIf you did not request a reset, you can ignore this email.`,
      });
    },
  };
}
