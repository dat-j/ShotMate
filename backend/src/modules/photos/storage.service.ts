import {
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

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

const SUPPORTED_CONTENT_TYPE = 'image/jpeg';
const MAX_LIST_KEYS_PER_BATCH = 1000; // S3 DeleteObjects hard limit per request

/**
 * StorageService — S3-compatible client (spec FR-S4-3, trả nợ D5).
 *
 * Uses `@aws-sdk/client-s3` against minio locally (S3 API-compatible) and can
 * point at any S3-compatible endpoint (GCS also exposes an S3-compatible XML
 * API, but the canonical GCS driver is `@google-cloud/storage` — out of scope
 * here; this class is the minio/local + S3-compatible driver named per the
 * shared interface).
 *
 * Bucket name is read from `GCS_BUCKET` (not `STORAGE_BUCKET`) intentionally:
 * the env var name is kept stable across the minio (local/dev) and eventual
 * GCS (prod) backends so switching providers later never requires renaming
 * config — only swapping the client/credentials.
 *
 * Signing uses `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` — a key pair
 * dedicated to object storage, NEVER `JWT_SECRET` (finding L2, Sprint 3
 * review: reusing the JWT signing secret to sign storage URLs would let a
 * storage key leak compromise auth, and vice versa).
 */
@Injectable()
export class StorageService implements IStorageService {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(private readonly config: ConfigService) {
    const endpoint = this.config.get<string>('STORAGE_ENDPOINT') || undefined;
    const region = this.config.get<string>('STORAGE_REGION') ?? 'auto';
    const accessKeyId = this.config.get<string>('STORAGE_ACCESS_KEY') ?? '';
    const secretAccessKey = this.config.get<string>('STORAGE_SECRET_KEY') ?? '';

    this.bucket = this.config.get<string>('GCS_BUCKET') ?? 'shotmate-photos-dev';

    this.client = new S3Client({
      endpoint,
      region,
      // minio (path-style buckets) needs forcePathStyle; harmless for GCS's
      // S3-compatible endpoint (also path-style) if used that way later.
      forcePathStyle: true,
      credentials: { accessKeyId, secretAccessKey },
    });
  }

  async createUploadUrl(
    objectPath: string,
    _contentType: string,
  ): Promise<{ uploadUrl: string; expiresAt: Date }> {
    const ttlSeconds = this.config.get<number>('SIGNED_URL_TTL_SECONDS') ?? 900;

    // Content-type is always image/jpeg here (PhotosService already rejects
    // anything else with 400 UNSUPPORTED_CONTENT_TYPE before reaching this
    // call) — the signed PUT is pinned to that type regardless of the
    // caller-supplied value, so a signed URL can never be reused to upload a
    // different content-type.
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: objectPath,
      ContentType: SUPPORTED_CONTENT_TYPE,
    });

    const uploadUrl = await getSignedUrl(this.client, command, { expiresIn: ttlSeconds });
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    return { uploadUrl, expiresAt };
  }

  async getObjectBase64(objectPath: string): Promise<string> {
    const result = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: objectPath }),
    );
    const bytes = await result.Body?.transformToByteArray();
    return Buffer.from(bytes ?? new Uint8Array()).toString('base64');
  }

  async deletePrefix(prefix: string): Promise<void> {
    let continuationToken: string | undefined;

    do {
      const listed = await this.client.send(
        new ListObjectsV2Command({
          Bucket: this.bucket,
          Prefix: prefix,
          ContinuationToken: continuationToken,
        }),
      );

      const keys = (listed.Contents ?? [])
        .map((obj) => obj.Key)
        .filter((key): key is string => Boolean(key));

      for (let i = 0; i < keys.length; i += MAX_LIST_KEYS_PER_BATCH) {
        const batch = keys.slice(i, i + MAX_LIST_KEYS_PER_BATCH);
        await this.client.send(
          new DeleteObjectsCommand({
            Bucket: this.bucket,
            Delete: { Objects: batch.map((Key) => ({ Key })) },
          }),
        );
      }

      continuationToken = listed.IsTruncated ? listed.NextContinuationToken : undefined;
    } while (continuationToken);
  }
}
