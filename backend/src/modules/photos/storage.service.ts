import { createHmac } from 'node:crypto';

import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { AppError } from '../../common/http/http-error.filter';

/**
 * StorageService contract — abstract away the cloud storage provider so the
 * rest of the app (photos/analysis) never depends on a concrete SDK
 * (spec FR-S3-2). A real GCS/minio implementation can be swapped in without
 * touching callers.
 */
export interface IStorageService {
  createUploadUrl(
    objectPath: string,
    contentType: string,
  ): Promise<{ uploadUrl: string; expiresAt: Date }>;
  getObjectBase64(objectPath: string): Promise<string>;
  deletePrefix(prefix: string): Promise<void>;
}

/**
 * Placeholder StorageService — no cloud SDK installed yet (`@google-cloud/storage`
 * and `@aws-sdk` are intentionally NOT dependencies, spec constraint). Builds a
 * signed-URL-shaped response deterministically via HMAC(JWT_SECRET) so the
 * upload-url endpoint is fully testable without network access.
 *
 * `getObjectBase64` / `deletePrefix` need an actual network round-trip to the
 * bucket — until the real client is wired they throw 503 STORAGE_UNAVAILABLE
 * (spec Availability: "Redis chết → ... API trả 503"; same posture applies to
 * storage backend not yet wired).
 *
 * // TODO: real GCS client (Sprint 3 deploy) — swap the body of createUploadUrl
 * // (V4 signed URL via @google-cloud/storage) and getObjectBase64/deletePrefix
 * // (bucket.file(...).download() / bucket.deleteFiles({prefix})) behind this
 * // same interface. Callers (PhotosService, ReviewProcessor, UsersService)
 * // depend only on the interface above.
 */
@Injectable()
export class StorageService implements IStorageService {
  constructor(private readonly config: ConfigService) {}

  createUploadUrl(
    objectPath: string,
    _contentType: string,
  ): Promise<{ uploadUrl: string; expiresAt: Date }> {
    const ttlSeconds = this.config.get<number>('SIGNED_URL_TTL_SECONDS') ?? 900;
    const bucket = this.config.get<string>('GCS_BUCKET') ?? 'shotmate-photos-dev';
    const endpoint =
      this.config.get<string>('STORAGE_ENDPOINT') ?? 'https://storage.googleapis.com';
    const secret = this.config.get<string>('JWT_SECRET') ?? 'dev-secret';

    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);
    const expiryEpoch = Math.floor(expiresAt.getTime() / 1000);
    const sig = createHmac('sha256', secret)
      .update(`${objectPath}:${expiryEpoch}`)
      .digest('hex');

    const uploadUrl = `${endpoint}/${bucket}/${objectPath}?X-Goog-Expires=${ttlSeconds}&X-Goog-Date=${expiryEpoch}&sig=${sig}`;

    return Promise.resolve({ uploadUrl, expiresAt });
  }

  getObjectBase64(_objectPath: string): Promise<string> {
    throw new AppError(
      503,
      'STORAGE_UNAVAILABLE',
      'Storage backend chưa được cấu hình (chờ GCS client Sprint 3 deploy)',
    );
  }

  deletePrefix(_prefix: string): Promise<void> {
    throw new AppError(
      503,
      'STORAGE_UNAVAILABLE',
      'Storage backend chưa được cấu hình (chờ GCS client Sprint 3 deploy)',
    );
  }
}
