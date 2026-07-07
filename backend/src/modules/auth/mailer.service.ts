import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import nodemailer, { Transporter } from 'nodemailer';

/**
 * MailerService — gửi magic link qua SMTP (local: mailpit, không auth).
 * Token raw KHÔNG bao giờ log — chỉ nằm trong body email (spec Rule 6,
 * security.md "Không log base64 ảnh/JWT/token").
 */
@Injectable()
export class MailerService {
  private readonly logger = new Logger(MailerService.name);
  private readonly transporter: Transporter;
  private readonly from: string;
  private readonly baseUrl: string;

  constructor(private readonly config: ConfigService) {
    this.from = this.config.get<string>('SMTP_FROM') ?? 'noreply@shotmate.app';
    this.baseUrl =
      this.config.get<string>('MAGIC_LINK_BASE_URL') ??
      'https://shotmate.app/auth/verify';

    const user = this.config.get<string>('SMTP_USER');
    const pass = this.config.get<string>('SMTP_PASSWORD');

    this.transporter = nodemailer.createTransport({
      host: this.config.get<string>('SMTP_HOST') ?? 'localhost',
      port: this.config.get<number>('SMTP_PORT') ?? 1025,
      // local (mailpit) không cần auth; prod (Brevo) bắt buộc — chỉ set
      // field `auth` khi có credentials để không phá luồng local hiện tại.
      secure: false,
      ...(user && pass ? { auth: { user, pass } } : {}),
    });
  }

  async sendMagicLink(email: string, token: string): Promise<void> {
    const url = `${this.baseUrl}?token=${token}`;

    this.logger.debug(`Sending magic link email to ${email}`);

    await this.transporter.sendMail({
      from: this.from,
      to: email,
      subject: 'ShotMate — Đăng nhập của bạn',
      text: `Bấm vào link sau để đăng nhập ShotMate (hết hạn sau ít phút): ${url}`,
      html: `<p>Bấm vào link sau để đăng nhập ShotMate (hết hạn sau ít phút):</p><p><a href="${url}">${url}</a></p>`,
    });
  }
}
