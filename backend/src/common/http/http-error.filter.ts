import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { FastifyReply } from 'fastify';

/**
 * Error envelope thống nhất (spec §API Changes, System Design §7):
 *   { "error": { "code": "UPPER_SNAKE", "message": "...", "details"?: {...} } }
 *
 * KHÔNG bao giờ lộ stack trace / SQL trong response (CWE-209). 5xx trả
 * INTERNAL chung chung; chi tiết chỉ vào log server.
 */
export class AppError extends HttpException {
  constructor(
    status: number,
    readonly code: string,
    message: string,
    readonly details?: unknown,
  ) {
    super({ code, message, details }, status);
  }
}

interface ErrorBody {
  code: string;
  message: string;
  details?: unknown;
}

@Catch()
export class HttpErrorFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpErrorFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const reply = host.switchToHttp().getResponse<FastifyReply>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let body: ErrorBody = { code: 'INTERNAL', message: 'Internal server error' };

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const res = exception.getResponse();
      body = this.normalize(status, res);
    }

    if (status >= 500) {
      // Chi tiết chỉ vào log — không rời server.
      this.logger.error(
        `${status} ${body.code}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
      body = { code: 'INTERNAL', message: 'Internal server error' };
    }

    void reply.status(status).send({ error: body });
  }

  private normalize(status: number, res: unknown): ErrorBody {
    if (typeof res === 'string') {
      return { code: this.defaultCode(status), message: res };
    }
    if (res && typeof res === 'object') {
      const obj = res as Record<string, unknown>;
      // AppError: { code, message, details }
      if (typeof obj.code === 'string' && typeof obj.message === 'string') {
        return {
          code: obj.code,
          message: obj.message,
          details: obj.details,
        };
      }
      // Nest ValidationPipe / default: { message, error, statusCode }
      const message = Array.isArray(obj.message)
        ? obj.message.join('; ')
        : typeof obj.message === 'string'
          ? obj.message
          : this.defaultMessage(status);
      return { code: this.defaultCode(status), message };
    }
    return { code: this.defaultCode(status), message: this.defaultMessage(status) };
  }

  private defaultCode(status: number): string {
    switch (status) {
      case 400:
        return 'VALIDATION_FAILED';
      case 401:
        return 'AUTH_TOKEN_INVALID';
      case 403:
        return 'FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      case 422:
        return 'VALIDATION_FAILED';
      case 429:
        return 'RATE_LIMITED';
      default:
        return 'INTERNAL';
    }
  }

  private defaultMessage(status: number): string {
    return status >= 500 ? 'Internal server error' : 'Request failed';
  }
}
