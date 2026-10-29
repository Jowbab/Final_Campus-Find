import nodemailer from 'nodemailer';

export class SmtpEmailGateway {
  constructor(env = process.env) {
    this.from = env.SMTP_FROM;
    if (!env.SMTP_HOST || !this.from) {
      this.transport = null;
      return;
    }
    this.transport = nodemailer.createTransport({
      host: env.SMTP_HOST,
      port: Number(env.SMTP_PORT ?? 587),
      secure: env.SMTP_SECURE === 'true',
      auth: env.SMTP_USER
        ? { user: env.SMTP_USER, pass: env.SMTP_PASSWORD ?? '' }
        : undefined,
      connectionTimeout: 10_000,
      greetingTimeout: 10_000,
      socketTimeout: 15_000,
    });
  }

  async sendVerificationCode({ to, code }) {
    await this.#send({
      to,
      subject: 'Verify your CampusFind email',
      text: `Your CampusFind verification code is ${code}. It expires in 15 minutes.`,
    });
  }

  async sendPasswordResetCode({ to, code }) {
    await this.#send({
      to,
      subject: 'Reset your CampusFind password',
      text: `Your CampusFind password reset code is ${code}. It expires in 10 minutes. If you did not request this, ignore this email.`,
    });
  }

  async #send({ to, subject, text }) {
    if (!this.transport) throw new Error('SMTP email delivery is not configured');
    await this.transport.sendMail({ from: this.from, to, subject, text });
  }
}
