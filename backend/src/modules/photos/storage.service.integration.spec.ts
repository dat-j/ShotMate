import {
  CreateBucketCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { ConfigService } from '@nestjs/config';
import { beforeAll, describe, expect, it } from 'vitest';

import { StorageService } from './storage.service';

/**
 * Integration test (spec FR-S4-3, FR-S4-7) — hits a REAL minio instance from
 * docker-compose (`infra/docker-compose.yml`), not a mock. Run explicitly via
 * `npm run test:integration` after `docker compose up -d minio`. Excluded
 * from the default `npm test` gate (see vitest.integration.config.ts).
 */
const ENDPOINT = process.env.STORAGE_ENDPOINT ?? 'http://localhost:9000';
const ACCESS_KEY = process.env.STORAGE_ACCESS_KEY ?? 'shotmate';
const SECRET_KEY = process.env.STORAGE_SECRET_KEY ?? 'shotmate-local';
const BUCKET = process.env.GCS_BUCKET ?? 'shotmate-photos-dev';

function config(overrides: Record<string, unknown> = {}) {
  const values: Record<string, unknown> = {
    STORAGE_ENDPOINT: ENDPOINT,
    STORAGE_ACCESS_KEY: ACCESS_KEY,
    STORAGE_SECRET_KEY: SECRET_KEY,
    STORAGE_REGION: 'auto',
    GCS_BUCKET: BUCKET,
    SIGNED_URL_TTL_SECONDS: 900,
    ...overrides,
  };
  return { get: (key: string) => values[key] } as unknown as ConfigService;
}

/** Ensures the bucket exists before the suite runs (minio does not auto-create it). */
async function ensureBucket() {
  const client = new S3Client({
    endpoint: ENDPOINT,
    region: 'auto',
    forcePathStyle: true,
    credentials: { accessKeyId: ACCESS_KEY, secretAccessKey: SECRET_KEY },
  });
  try {
    await client.send(new HeadBucketCommand({ Bucket: BUCKET }));
  } catch {
    await client.send(new CreateBucketCommand({ Bucket: BUCKET }));
  }
  return client;
}

describe('StorageService (integration — minio thật, spec FR-S4-3)', () => {
  let rawClient: S3Client;

  beforeAll(async () => {
    rawClient = await ensureBucket();
  }, 20000);

  it('createUploadUrl trả presigned PUT URL thật, dùng được để upload lên minio', async () => {
    const svc = new StorageService(config());
    const objectPath = `photos/integration-test/${Date.now()}-upload.jpg`;

    const { uploadUrl, expiresAt } = await svc.createUploadUrl(objectPath, 'image/jpeg');

    expect(uploadUrl).toContain(BUCKET);
    expect(uploadUrl).toMatch(/^http/);
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now());

    const body = Buffer.from('fake-jpeg-bytes-for-integration-test');
    const putRes = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'image/jpeg' },
      body,
    });

    expect(putRes.ok).toBe(true);
  });

  it('getObjectBase64 đọc lại đúng nội dung đã upload', async () => {
    const svc = new StorageService(config());
    const objectPath = `photos/integration-test/${Date.now()}-roundtrip.jpg`;
    const original = Buffer.from('round-trip-content-check');

    await rawClient.send(
      new PutObjectCommand({
        Bucket: BUCKET,
        Key: objectPath,
        Body: original,
        ContentType: 'image/jpeg',
      }),
    );

    const base64 = await svc.getObjectBase64(objectPath);

    expect(Buffer.from(base64, 'base64').toString('utf-8')).toBe(original.toString('utf-8'));
  });

  it('deletePrefix xoá toàn bộ object dưới prefix', async () => {
    const svc = new StorageService(config());
    const prefix = `photos/integration-test-delete-${Date.now()}/`;
    const keys = [`${prefix}a.jpg`, `${prefix}b.jpg`, `${prefix}sub/c.jpg`];

    for (const key of keys) {
      await rawClient.send(
        new PutObjectCommand({
          Bucket: BUCKET,
          Key: key,
          Body: Buffer.from('x'),
          ContentType: 'image/jpeg',
        }),
      );
    }

    await svc.deletePrefix(prefix);

    // Đối tượng đã xoá — getObjectBase64 phải throw (NoSuchKey) cho từng key.
    for (const key of keys) {
      await expect(svc.getObjectBase64(key)).rejects.toBeTruthy();
    }
  });

  it('KHÔNG dùng JWT_SECRET để ký URL — presign vẫn hoạt động dù JWT_SECRET không được set trong ConfigService', async () => {
    // config() ở trên không có JWT_SECRET key nào cả — nếu StorageService lỡ
    // đọc `this.config.get('JWT_SECRET')` nó sẽ nhận `undefined`, và nếu logic
    // cũ (HMAC theo JWT_SECRET) còn sót lại, signature sẽ sai / URL sẽ không
    // hoạt động được với minio thật. Test này xác nhận URL vẫn PUT thành công
    // chỉ với STORAGE_ACCESS_KEY/STORAGE_SECRET_KEY.
    const svc = new StorageService(config());
    const objectPath = `photos/integration-test/${Date.now()}-no-jwt-secret.jpg`;

    const { uploadUrl } = await svc.createUploadUrl(objectPath, 'image/jpeg');
    const res = await fetch(uploadUrl, {
      method: 'PUT',
      headers: { 'Content-Type': 'image/jpeg' },
      body: Buffer.from('ok'),
    });

    expect(res.ok).toBe(true);
  });
});
