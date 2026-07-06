# Feature Specification: Sprint 3 — Backend + Monetization + Beta

<!--
Feature Specification
Filename: docs/specs/spec-sprint-3.md
Owner: Builder (/builder)
Handoff to: Builder (/builder), QA Engineer (/qa-engineer), Security Auditor (/security-auditor)
Purpose: Dev đọc và implement. QA đọc và test. Không cho phép mơ hồ.
-->

## Metadata

**Status:** Draft — chờ approve
**Author:** Đạt Trần
**Date:** 2026-07-06
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) (FR-8 sync, FR-9, FR-10, FR-11, FR-12 server-side; NFR-7, NFR-8)
**Related ADR:** [0002](../adr/0002-offline-first-backend-sprint-3.md) (offline-first, UUID client-side), [0004](../adr/0004-cloud-ai-provider-adapter.md) (adapter 2 provider), [0007](../adr/0007-native-owns-camera-session.md) (iOS module port)
**Related design:** [system-design-shotmate.md](../design/system-design-shotmate.md) §3 Backend Components, §5 API Design, §6 Data Model, §7 Security
**Related spec:** [spec-sprint-1.md](spec-sprint-1.md), [spec-sprint-2.md](spec-sprint-2.md) — Business Rules Sprint 1–2 tiếp tục có hiệu lực cho app

---

## Overview

Sprint 1–2 app đã coach hoàn chỉnh offline (Android). Sprint 3 mở đường lên cloud **mà không phá offline-first**: NestJS API trên Cloud Run (auth magic link + JWT, sync, credits, subscription) + review worker BullMQ gọi Claude/Gemini qua `AiReviewProvider` (đã scaffold sẵn trong `backend/`), và đưa app ra beta (Play Internal + TestFlight). Server chết → app mất review/sync/login, **guidance + score offline vẫn chạy nguyên vẹn**.

**Điểm xuất phát:** `backend/` đã có skeleton NestJS/Fastify (prefix `api/v1`), Prisma schema mirror ERD, `AiReviewService` failover + zod validation + prompt chung 2 provider, docker-compose local (postgres/redis/minio/mailpit). Sprint 3 = implement các module skeleton + wire app + hạ tầng release.

**Nợ kéo sang từ Sprint 2:** iOS native inference module (FR-S3-9) — bắt buộc cho beta TestFlight có coaching; đo accuracy scene classifier (ngoài spec này, xem spec-sprint-2 Rule 8).

---

## Business Rules

### Rule 0 — Kế thừa Sprint 1–2

Business Rules Sprint 1 (max 2 hint, frame không rời native, credit device-local cho score offline) và Sprint 2 áp dụng nguyên vẹn. Sprint 3 KHÔNG thay đổi bất kỳ hành vi realtime nào.

### Rule 1 — Offline-first bất khả xâm phạm

Mọi tính năng mới đều degrade gracefully: không mạng / server 5xx → nút Review AI disabled kèm lý do 1 dòng, sync im lặng chờ lần sau, login screen báo lỗi retry được. **Không có call mạng nào trên đường frame→hint hoặc capture→score offline.** Timeout mặc định Dio: connect 5s, receive 15s.

### Rule 2 — Credit: server là source of truth cho cloud review

- **Cloud review (FR-9)**: chỉ user đã login. Quota free **10 review/ngày** (theo ngày UTC của server), premium `quota = -1` (unlimited). Trừ credit **atomic server-side ngay khi enqueue** (transaction `UPDATE ... RETURNING`); 2 request song song khi còn 1 lượt → đúng 1 request pass (EC-S3-1).
- **Review thất bại chung cuộc** (hết retry, `status = failed`) → **hoàn 1 credit** trong cùng transaction cập nhật status.
- **Score on-device** giữ nguyên device-local 10 lượt/ngày như Sprint 1 (không đổi hành vi, không sync counter).

> **Assumption:** Pool credit cloud review (server, ngày UTC) và pool score offline (local, ngày local) là **hai counter độc lập** — PRD FR-12 chỉ yêu cầu "server-side Sprint 3" cho phần ăn tiền (cloud review). Gộp một pool cần sync counter offline↔online, phức tạp không đáng ở beta.

### Rule 3 — Không tin client về subscription

Premium status do server tính từ IAP receipt/entitlement — client chỉ hiển thị. App gửi receipt/token → server verify → cập nhật `Subscription` → `GET /me` trả plan hiện hành. Client tự khai premium không có hiệu lực (credit quota lấy từ DB server).

> **Assumption:** Dùng **RevenueCat** (đề xuất sẵn trong PRD Open Questions + roadmap "quyết định RevenueCat trước sprint"): SDK `purchases_flutter` phía app, webhook RevenueCat → backend cập nhật Subscription; `POST /subscriptions/verify` giữ làm đường fallback khi webhook trễ. Nếu chốt IAP native trực tiếp → cần ADR mới + thêm ~3 ngày effort verify 2 store.

### Rule 4 — Ảnh chỉ rời thiết bị khi user bấm Review AI (opt-in per-photo)

Không auto-upload bất kỳ ảnh nào (NFR-3). Flow: user bấm "Review AI" trên Score screen → client resize ≤ 1568px cạnh dài, JPEG quality 85 → xin signed URL (TTL 15 phút, chỉ chấp nhận `image/jpeg`, max 10MB) → PUT lên GCS → gọi enqueue review. Sync history (Rule 5) **chỉ đẩy metadata**, không bao giờ đẩy pixel.

### Rule 5 — Sync: UUID client thắng, last-write-wins theo `taken_at`

- Photo/Analysis/Score dùng UUID sinh tại client từ Sprint 1 (ADR-0002) — server **upsert theo id, không bao giờ cấp lại id**.
- Conflict (cùng id, nội dung khác): bản có `taken_at`/`created_at` mới hơn thắng; server trả bản thắng trong `conflicts[]` để client ghi đè local.
- Batch tối đa **500 record/request**; client đẩy `WHERE synced_at IS NULL`, nhận 200 → set `synced_at`. Sync chạy: sau login thành công + mỗi lần app foreground có mạng + sau mỗi capture khi online (debounce 30s).

### Rule 6 — Auth: magic link single-use, JWT rotation, phát hiện reuse

- Magic link: token 32 byte random, **lưu dạng SHA-256 hash**, TTL **10 phút**, **single-use** (verify xong set `used_at`).
- JWT: access **15 phút** / refresh **30 ngày**, refresh **rotation** mỗi lần dùng. Refresh token cũ bị dùng lại (reuse detection) → **revoke cả token family**, buộc login lại (EC-S3-5).
- Response `POST /auth/magic-link` luôn **202** bất kể email tồn tại hay không (không lộ user tồn tại).

### Rule 7 — AI provider: primary theo config, failover tự động, retry có trần

Primary đọc từ `AI_REVIEW_PRIMARY` (env; production đọc Firebase Remote Config, cache 5 phút). Provider lỗi → thử provider còn lại ngay trong request (đã implement trong `AiReviewService`). Cả hai lỗi → BullMQ retry **3 lần, exponential backoff base 2s**; hết retry → `status=failed` + hoàn credit (Rule 2) + client hiển thị "Thử lại sau". Output LLM **phải pass zod `reviewResultSchema`** mới được lưu — fail schema tính là provider lỗi (failover luôn).

### Rule 8 — Rate limiting

> **Assumption:** con số khởi điểm, tune qua Cloud Armor/config sau beta:

| Scope | Limit | Vượt → |
|-------|-------|--------|
| `POST /auth/magic-link` | 3/email/15 phút VÀ 10/IP/giờ | 429 `RATE_LIMITED` |
| `POST /photos/:id/review` | 10/user/phút (credit đã chặn theo ngày) | 429 |
| Toàn API authenticated | 60 req/phút/user | 429 |
| Toàn API theo IP | 300 req/phút/IP (Fastify rate-limit; Cloud Armor tầng ngoài) | 429 |

### Rule 9 — Beta gate

Trước khi mời tester ngoài: security checklist `.claude/rules/security.md` pass cho backend (audit bởi /security-auditor), crash-free > 99.5% trong internal testing ≥ 3 ngày, benchmark 50 ảnh calibration hoàn thành (Validation ADR-0004), cost đo thật ≤ $0.01/ảnh.

### Rule 10 — Thứ tự cắt scope nếu trễ (roadmap risk, quyết định trước — không đàm phán giữa sprint)

1. **Cắt trước:** Sync đa thiết bị (FR-S3-6) — dời sau beta, app vẫn offline-first nên không ai mất dữ liệu.
2. **Cắt nhì:** iOS native module (FR-S3-9) → beta **Android-only** (Play Internal), TestFlight dời.
3. **Cắt ba:** Feedback endpoint + UI (FR-S3-10).
4. **Không bao giờ cắt:** auth, cloud review pipeline, credits server-side, subscription verify.

---

## Functional Requirements

### FR-S3-1: Auth — magic link + JWT

**Backend** (`AuthModule` — hiện là skeleton rỗng):
- `POST /auth/magic-link`: validate email (class-validator), tạo token (Rule 6), gửi mail qua SMTP (local: mailpit). Link dạng `https://shotmate.app/auth/verify?token=...` fallback web + deep link `shotmate://auth/verify?token=...`.
- `POST /auth/verify`: token hợp lệ → tạo user nếu chưa có (email = định danh) → trả `{ accessToken, refreshToken, user }`.
- `POST /auth/refresh`: rotation + reuse detection (Rule 6).
- Guard JWT global, decorator `@Public()` cho 3 route auth. Payload JWT: `{ sub: userId, plan }` — plan chỉ để hint UI, authorization thật luôn query DB.

**App** (`features/auth/` mới):
- `LoginScreen` (nhập email → "kiểm tra hộp thư"), deep link handler (GoRouter route `/auth/verify`), `AuthRepository` (Dio) + `authStateProvider` (NotifierProvider).
- Token lưu **secure storage** (Keychain/EncryptedSharedPreferences qua `flutter_secure_storage`), KHÔNG lưu Drift/SharedPreferences.
- Dio interceptor: gắn access token, 401 → thử refresh 1 lần → fail thì logout về trạng thái anonymous (app vẫn dùng offline bình thường — Rule 1).
- Login là **tuỳ chọn**: entry point ở Settings ("Đăng nhập để review AI & sync"), không chặn flow camera.

> **Assumption:** `flutter_secure_storage` thêm vào golden path (an toàn hơn Drift plaintext cho token; không phải "local storage" nghiệp vụ nên không vi phạm ADR-0005).

### FR-S3-2: Photo upload qua signed URL

**Backend** (`PhotosModule`):
- `POST /photos/upload-url`: nhận `{ photoId, contentType }` → upsert Photo metadata (owner = JWT user) → trả signed URL PUT (TTL 15 phút, `image/jpeg` only, max 10MB qua `X-Goog-Content-Length-Range`). Storage path: `photos/{userId}/{photoId}.jpg`.
- Local dev: minio (S3-compatible) sau interface `StorageService` — implementation GCS + minio chọn theo env.

**App:** util resize ảnh (≤1568px cạnh dài, JPEG q85 — dùng `image` package hoặc native) chạy trong isolate; upload PUT bằng Dio.

### FR-S3-3: Cloud AI review pipeline (FR-9)

**Backend** (`AnalysisModule` + worker):
- `POST /photos/:id/review`: kiểm tra ownership → ảnh đã upload (`storagePath != null`, ngược lại 422) → không có review `queued|processing` cho photo này (ngược lại 409) → trừ credit atomic (Rule 2) → tạo `Analysis{ kind: cloud, status: queued, provider: pending }` → enqueue BullMQ job `{ analysisId }` → **202** `{ reviewId, status, creditsRemaining }`.
- Worker (BullMQ processor, service Cloud Run riêng, cùng codebase, entry `src/main.worker.ts`): tải ảnh từ GCS → `AiReviewService.review()` (failover Rule 7) → lưu `result` + `Score` + `provider`, `status=done`. Concurrency 5. Fail chung cuộc → `status=failed` + refund.
- `GET /photos/:id/review`: trả `ReviewResult` theo shape System Design §5 (status/provider/scores/explanation/suggestions).
- Queue: BullMQ trên Redis (`REDIS_URL`), queue name `ai-review`. Dependencies thêm: `bullmq`, `ioredis`, `@nestjs/jwt`, `@prisma/client`, `nodemailer`, `@google-cloud/storage`, `@fastify/rate-limit`, `class-validator`.

**App** (`features/review/` mới):
- Score screen thêm nút "Review AI ✨" (kèm số credit còn lại từ `/me`): resize → upload (FR-S3-2) → enqueue → poll `GET review` mỗi 2s, tối đa 90s (quá → hiển thị "đang xử lý, quay lại sau", history sẽ cập nhật lần mở sau).
- Kết quả lưu vào bảng Drift `analyses` hiện có (`kind=cloud`, `provider=claude|gemini`, `result` JSON) — **không đổi Drift schema**. UI hiển thị explanation + suggestions dưới score offline, ghi rõ provider.

### FR-S3-4: Credits server-side (FR-12)

`CreditsModule`: bảng `credits` (đã có trong Prisma schema, unique `[userId, day]`). Trừ/hoàn theo Rule 2 — một transaction duy nhất:

```sql
INSERT INTO credits (id, user_id, day, used, quota)
VALUES ($1, $2, CURRENT_DATE, 1, $quota)
ON CONFLICT (user_id, day) DO UPDATE SET used = credits.used + 1
  WHERE credits.used < credits.quota OR credits.quota = -1
RETURNING used, quota;   -- 0 row = hết quota → 402
```

`quota` snapshot lúc tạo row từ plan hiện hành (premium: -1). `GET /me` trả `credits: { usedToday, quota, remainingToday }` (`-1` = unlimited).

### FR-S3-5: Subscription Premium (FR-11)

- **App:** `purchases_flutter` (RevenueCat) + `PaywallScreen` (1 gói tháng; giá hiển thị từ store). Điểm vào: hết credit (CTA trên 402), Settings.
- **Backend** (`SubscriptionsModule`): `POST /webhooks/revenuecat` (xác thực bằng `Authorization` header secret) cập nhật `Subscription{ plan, store, expiresAt, receiptRef }`; `POST /subscriptions/verify` fallback — nhận app user id + fetch entitlement từ RevenueCat REST API.
- Premium hết hạn (`expiresAt < now`) → plan tính là `free` khi đọc (không cần cron; EC-S3-9).
- Giá Premium: **chốt trước khi submit store** — xem Open Questions.

### FR-S3-6: Sync history đa thiết bị (FR-8, FR-10) — *cắt đầu tiên nếu trễ (Rule 10)*

- `POST /sync`: body `{ photos[], analyses[], scores[] }` (≤500 record tổng), upsert theo Rule 5, response `{ accepted: number, conflicts: [...] }`.
- `GET /photos?cursor&limit=20` (max 100, cursor-based theo `taken_at DESC`) — pull chiều về cho thiết bị mới.
- **App:** `SyncService` (features/history): đẩy `synced_at IS NULL` theo trigger Rule 5; pull khi login trên thiết bị mới. Ảnh pixel KHÔNG sync (Rule 4) — thiết bị khác thấy metadata + score, placeholder ảnh.

### FR-S3-7: Account management

- `GET /me`: user + subscription + credits (một round-trip cho UI).
- `DELETE /me`: xoá user cascade (Prisma đã khai `onDelete: Cascade`) + xoá GCS prefix `photos/{userId}/` + revoke tokens → 204. **Bắt buộc theo App Store Guideline 5.1.1(v)** (app có account thì phải xoá được account trong app). Local data giữ nguyên (thuộc máy user).
- **App:** Settings thêm section Account: email, nút logout, nút "Xoá tài khoản" (confirm 2 bước, nói rõ ảnh cloud bị xoá, data local giữ).

### FR-S3-8: Observability + release infra

- **Backend:** pino structured JSON (redact email — PII duy nhất), OpenTelemetry OTLP → Cloud Trace (span: API→queue→provider), health check `GET /healthz` (public, cho Cloud Run). Alert: error rate > 5%, queue depth > 100, provider failure rate > 20%.
- **App:** `flutterfire configure` (nợ Sprint 1 §2.4) — Crashlytics + Analytics events đã liệt kê spec 1–2 + mới: `login_completed`, `review_requested`, `review_completed{provider, latencyMs}`, `review_failed`, `paywall_shown`, `purchase_completed`, `sync_completed{count}`.
- **CI/CD:** GitHub Actions mở rộng `infra/github-actions/ci.yml`: backend lint+test+build Docker → deploy Cloud Run dev (auto) → staging/prod manual approve. App: Fastlane lane `beta` → TestFlight + Play Internal. Secrets qua GCP Secret Manager / GitHub OIDC — không secrets trong repo.

### FR-S3-9: iOS native inference module (nợ Sprint 2, ADR-0007) — *cắt nhì (Rule 10)*

Port module Android sang Swift: AVCaptureVideoDataOutput (một owner camera theo ADR-0007), MediaPipe pose GPU + ML Kit face/labeling + exposure/horizon/pitch/thermal (`ProcessInfo.thermalState`) → EventChannel cùng payload **schemaVersion 2** (contract trong `NATIVE_MODULE.md`, Android là tham chiếu). Gate: frame→hint < 100ms p90 trên iPhone 12; fail → beta iOS dời (Rule 10).

### FR-S3-10: Feedback (chuẩn bị tuning) — *cắt ba (Rule 10)*

`POST /feedback` (`targetKind ∈ {hint, score, review}`, `rating ∈ {1, -1}`, comment ≤ 500 ký tự). App: nút 👍/👎 trên kết quả cloud review (target chính cho benchmark ADR-0004). Offline → bỏ qua im lặng (không queue).

---

## API Changes

Base: `https://api.shotmate.app/api/v1` (prefix đã set trong `main.ts`). Auth: `Authorization: Bearer <access>`. Error envelope thống nhất:

```typescript
{ "error": { "code": "UPPER_SNAKE", "message": "human-readable", "details": {...}? } }
```

| Method | Endpoint | Auth | Success | Errors |
|--------|----------|------|---------|--------|
| POST | `/auth/magic-link` | — | 202 `{}` (luôn, Rule 6) | 400 `VALIDATION_FAILED` (email sai định dạng) · 429 `RATE_LIMITED` |
| POST | `/auth/verify` | — | 200 `{accessToken, refreshToken, user}` | 401 `AUTH_LINK_INVALID` (sai/hết hạn/đã dùng — một code, không phân biệt để tránh oracle) |
| POST | `/auth/refresh` | refresh | 200 token pair mới | 401 `AUTH_TOKEN_INVALID` · 401 `AUTH_TOKEN_REUSED` (revoke family, EC-S3-5) |
| GET | `/me` | ✓ | 200 `{user, subscription{plan, expiresAt}, credits{usedToday, quota, remainingToday}}` | 401 |
| DELETE | `/me` | ✓ | 204 | 401 |
| POST | `/photos/upload-url` | ✓ | 201 `{uploadUrl, storagePath, expiresAt}` | 400 `UNSUPPORTED_CONTENT_TYPE` · 422 `VALIDATION_FAILED` (photoId không phải UUID) |
| POST | `/photos/:id/review` | ✓ | 202 `{reviewId, status: "QUEUED", creditsRemaining}` | 402 `CREDITS_EXHAUSTED` · 404 `PHOTO_NOT_FOUND` (gồm cả photo của user khác — không lộ tồn tại) · 409 `REVIEW_IN_PROGRESS` · 422 `PHOTO_NOT_UPLOADED` · 429 |
| GET | `/photos/:id/review` | ✓ | 200 `ReviewResult` (shape System Design §5) | 404 `REVIEW_NOT_FOUND` |
| GET | `/photos?cursor&limit` | ✓ | 200 `{items[], nextCursor?}` | 400 `VALIDATION_FAILED` (limit > 100) |
| POST | `/sync` | ✓ | 200 `{accepted, conflicts[]}` | 400 `BATCH_TOO_LARGE` (> 500) · 422 `VALIDATION_FAILED` |
| POST | `/subscriptions/verify` | ✓ | 200 `{plan, expiresAt}` | 400 `SUBSCRIPTION_INVALID_RECEIPT` |
| POST | `/webhooks/revenuecat` | secret header | 200 | 401 `WEBHOOK_UNAUTHORIZED` |
| POST | `/feedback` | ✓ | 201 `{id}` | 422 `VALIDATION_FAILED` |
| GET | `/healthz` | — | 200 `{status: "ok"}` | — |

Mọi endpoint authenticated trả 401 `AUTH_TOKEN_INVALID` khi thiếu/sai JWT; 500 trả `INTERNAL` không kèm stack trace (System Design §7).

**Platform channels (app nội bộ):** không đổi so với Sprint 2. FR-S3-9 chỉ port iOS lên cùng contract schemaVersion 2.

---

## Database Changes

### Server (Prisma — migration đầu tiên của repo)

Schema hiện có trong `backend/prisma/schema.prisma` giữ nguyên (mirror ERD). **Thêm 2 model** cho Rule 6:

```prisma
model MagicLinkToken {
  id        String    @id @default(uuid()) @db.Uuid
  email     String
  tokenHash String    @unique @map("token_hash")   // SHA-256, không lưu raw
  expiresAt DateTime  @map("expires_at")
  usedAt    DateTime? @map("used_at")
  createdAt DateTime  @default(now()) @map("created_at")

  @@index([email, createdAt])
  @@map("magic_link_tokens")
}

model RefreshToken {
  id        String    @id @default(uuid()) @db.Uuid
  userId    String    @map("user_id") @db.Uuid
  familyId  String    @map("family_id") @db.Uuid   // rotation chain — reuse → revoke cả family
  tokenHash String    @unique @map("token_hash")
  expiresAt DateTime  @map("expires_at")
  revokedAt DateTime? @map("revoked_at")

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([familyId])
  @@map("refresh_tokens")
}
```

(+ relation `refreshTokens RefreshToken[]` trên `User`.) Migration qua `prisma migrate dev` — **không** `prisma db push` (tech-strategy). Cron dọn token hết hạn: job BullMQ repeatable 1 lần/ngày, xoá `expires_at < now() - 7 days`.

### Local (Drift) — KHÔNG đổi schema

Schema v2 đã đủ: `photos.synced_at` (sync), `analyses.kind/provider/result` (chứa cloud review), `settings` (thêm key mới không cần migration). Token ở secure storage (FR-S3-1), không vào Drift.

---

## Security Requirements

Theo System Design §7 (STRIDE) + `.claude/rules/security.md`. Điểm enforce cụ thể:

| Yêu cầu | Implement |
|---------|-----------|
| Ownership check mọi resource | Service layer filter `userId` từ JWT — không bao giờ nhận userId từ body. Photo người khác → 404 (không phải 403 — không lộ tồn tại) |
| Token hash-at-rest | Magic link + refresh token lưu SHA-256; raw chỉ ở mail/client |
| Secrets | `.env` local (gitignored, có `.env.example`), GCP Secret Manager prod. CI không echo secrets. Không secrets trong diff (quality gate) |
| Input validation | class-validator DTO mọi endpoint; zod cho LLM output (`reviewResultSchema` — đã có) và webhook payload |
| Upload an toàn | Signed URL 15 phút, `image/jpeg` whitelist, 10MB cap, path server-sinh `photos/{userId}/{photoId}.jpg` — client không kiểm soát path (chống traversal/overwrite) |
| PII | Email duy nhất — mask trong pino log (`redact`). Ảnh: bucket private, đọc qua signed URL ngắn hạn. KHÔNG log base64 ảnh/JWT/token |
| Error hygiene | Envelope chuẩn, không stack trace/SQL trong response (CWE-209) |
| Webhook | RevenueCat Authorization header so sánh constant-time với secret |
| Audit | Log structured mọi thao tác credit trừ/hoàn + subscription thay đổi (Repudiation) |
| DoS | Rate limit Rule 8, BullMQ concurrency 5, Cloud Run max instances cap, body limit 1MB (ảnh không đi qua API — chỉ signed URL) |

Security audit (/security-auditor hoặc `/security-review`) chạy trước beta gate (Rule 9) — kết quả là artifact bắt buộc.

---

## Caching Impact

- **Redis:** BullMQ queue `ai-review` + rate-limit counters. **Không cache credit** — đọc/ghi thẳng Postgres transaction (Rule 2 cần atomic; ~20 req/s peak thừa sức, thêm cache = thêm nguồn sai lệch).
- **Remote Config** (`AI_REVIEW_PRIMARY`): cache in-memory 5 phút phía backend (Rule 7).
- **App:** `GET /me` cache in-memory per-session, invalidate sau review/purchase; kết quả review persist vào Drift `analyses` (offline đọc lại được — không refetch).

---

## Frontend Changes (Flutter)

### Routes (GoRouter — sub-route của `/` theo pattern hiện có trong `app_router.dart`)

| Route | Screen | Ghi chú |
|-------|--------|---------|
| `/login` | `LoginScreen` | Push từ Settings; không bao giờ là màn chặn |
| `/auth/verify` | deep link handler | `shotmate://auth/verify?token=...` → verify → pop về Settings |
| `/paywall` | `PaywallScreen` | Push từ CTA hết credit / Settings |

`ScoreScreen` mở rộng (nút Review AI + kết quả cloud), `SettingsScreen` thêm section Account. Không đổi route camera/score/history hiện có.

### State Management (Riverpod)

| Provider | Type | Vai trò |
|----------|------|---------|
| `authStateProvider` | NotifierProvider | anonymous / authenticated(user); đọc secure storage khi khởi động |
| `apiClientProvider` | Provider\<Dio\> | baseUrl theo flavor + auth interceptor (refresh 1 lần) |
| `meProvider` | FutureProvider | `/me` — credit + plan cho UI; invalidate sau review/purchase |
| `reviewControllerProvider` | AsyncNotifierProvider (family theo photoId) | state machine: idle → uploading → queued → polling → done/failed |
| `syncServiceProvider` | Provider | trigger theo Rule 5; không có UI riêng ngoài dòng "Đã đồng bộ" ở History |
| `subscriptionProvider` | NotifierProvider | wrap RevenueCat SDK + đối chiếu `/me` |

### Dependencies mới (pubspec)

`flutter_secure_storage`, `purchases_flutter`, `image` (resize isolate), `firebase_core` + `firebase_analytics` + `firebase_crashlytics` (nợ Sprint 1), `app_links` (deep link). Dio/uuid đã có sẵn.

---

## Event / Job Changes

| Loại | Chi tiết |
|------|----------|
| BullMQ `ai-review` | payload `{analysisId}`; concurrency 5; attempts 3, exponential backoff 2s; fail chung cuộc → status failed + refund (Rule 7) |
| BullMQ repeatable `token-cleanup` | 1 lần/ngày, xoá token hết hạn > 7 ngày |
| Webhook | `POST /webhooks/revenuecat` — INITIAL_PURCHASE / RENEWAL / CANCELLATION / EXPIRATION → upsert Subscription |
| Firebase Analytics | events liệt kê ở FR-S3-8 |

---

## Non-Functional Requirements

### Performance

| Operation | Target | Đo bằng |
|-----------|--------|---------|
| Cloud review end-to-end (submit → done) | < 10s p90 (NFR-7) | OTel trace API→queue→provider |
| API non-AI (auth/me/photos/sync) | < 300ms p95 (chưa tính cold start) | Cloud Monitoring |
| Cloud Run cold start (min-instances 0 ở beta) | < 3s, chấp nhận ở beta | — |
| `POST /sync` 500 records | < 3s p95 | Vitest + staging |
| Resize + upload ảnh (client, ảnh 12MP) | < 4s trên reference device | manual |
| Cost/ảnh review | ≤ $0.01 (NFR-8) | đo thật trong benchmark 50 ảnh |
| Frame→hint (không đổi) | < 100ms p90 — **Sprint 3 không được làm chậm** | Perf HUD regression check |
| iOS frame→hint (FR-S3-9) | < 100ms p90 trên iPhone 12 | Perf HUD |

### Availability

API 99.5%; app core 100% offline (Rule 1). Worker chết → job nằm queue, không mất (BullMQ persistence); Redis chết → review tạm dừng, API trả 503 `REVIEW_UNAVAILABLE` cho enqueue, mọi thứ khác sống.

### Scalability

Cloud Run autoscale 0→N, ~20 req/s peak (System Design §8) — không tối ưu sớm hơn mức này ở beta.

---

## Edge Cases

### EC-S3-1: Race trừ credit
**Condition:** Còn 1 credit, 2 request review song song.
**Expected:** Transaction atomic (FR-S3-4) — đúng 1 request 202, request kia 402 `CREDITS_EXHAUSTED`. Có integration test.

### EC-S3-2: Cả 2 AI provider fail
**Condition:** Claude + Gemini đều lỗi (hoặc output fail zod) qua 3 attempts.
**Expected:** `status=failed`, hoàn 1 credit (kiểm chứng được qua `/me`), client hiển thị "Thử lại sau" + nút retry (retry = request mới, trừ credit mới).

### EC-S3-3: Mua premium giữa ngày khi đã hết 10 lượt
**Expected:** Webhook/verify cập nhật plan → request review tiếp theo tạo/ghi row credit ngày đó với `quota=-1` → pass ngay. Không cần đợi 00:00.

### EC-S3-4: Magic link mở trên thiết bị khác thiết bị gửi
**Expected:** Vẫn login thành công (token không bind device — Rule 6 chỉ yêu cầu single-use + TTL). Link bấm lần 2 → 401 `AUTH_LINK_INVALID`.

### EC-S3-5: Refresh token bị dùng lại (nghi đánh cắp)
**Expected:** Server revoke cả family, cả kẻ cắp lẫn user thật phải login lại; app về anonymous, camera/score offline vẫn chạy (Rule 1). Log cảnh báo.

### EC-S3-6: Sync conflict cùng UUID
**Condition:** Cùng photo id từ 2 thiết bị, `capture_meta` khác nhau.
**Expected:** LWW theo `taken_at` (Rule 5); bản thua nhận bản thắng qua `conflicts[]` và ghi đè local. Không duplicate row (upsert theo id).

### EC-S3-7: Signed URL hết hạn giữa upload
**Expected:** GCS trả 403 → client xin URL mới + retry đúng 1 lần → vẫn fail thì báo lỗi, KHÔNG trừ credit (credit chỉ trừ ở bước enqueue, sau upload thành công).

### EC-S3-8: Bấm Review AI khi offline / server chết
**Expected:** Nút disabled kèm "Cần mạng để review" (client biết trước qua connectivity); server 5xx → thông báo lỗi retry được. Không có offline queue cho review ở beta (đơn giản, tránh surprise cost).

### EC-S3-9: Subscription hết hạn / refund
**Expected:** `expiresAt < now` → plan đọc ra `free` ngay (không cần cron); review đang chạy vẫn hoàn thành bình thường. Webhook EXPIRATION chỉ là xác nhận sớm.

### EC-S3-10: Login sau khi đã có history local (anonymous → user)
**Expected:** Toàn bộ photos `synced_at IS NULL` (từ trước login) sync lên gắn userId mới — UUID client giữ nguyên, không mất/đổi id. History không thay đổi gì về UI.

### EC-S3-11: Xoá account
**Expected:** DELETE `/me` → 204; DB cascade + GCS prefix xoá + token revoke. Data local (ảnh, score) GIỮ NGUYÊN trên máy — confirm dialog nói rõ điều này.

### EC-S3-12: Ảnh sai định dạng/quá lớn
**Expected:** Content-type khác `image/jpeg` → 400 tại upload-url; > 10MB → GCS chặn qua content-length-range. Không trừ credit (chưa tới bước enqueue).

### EC-S3-13: Poll quá 90s chưa done
**Expected:** Client dừng poll, hiển thị "đang xử lý — kết quả sẽ có trong History"; lần mở Score screen sau poll lại 1 lần. Job server vẫn chạy độc lập.

---

## Acceptance Criteria

> Backend verify trên local stack (docker-compose) + môi trường dev Cloud Run. App verify trên Android reference device; iOS theo FR-S3-9 (nếu không cắt).

- [ ] Auth e2e local: nhập email → nhận mail (mailpit) → deep link → login; access hết hạn tự refresh; reuse refresh token cũ → cả family bị revoke (test tự động)
- [ ] Review e2e với ảnh thật: bấm Review AI → kết quả < 10s p90 (đo ≥ 20 lần trên dev env), hiển thị explanation tiếng Việt + suggestions, lưu Drift đọc lại được offline
- [ ] Failover test (Validation ADR-0004): sai key provider primary → review vẫn done qua provider còn lại, `provider` field phản ánh đúng
- [ ] Cả 2 provider fail → status failed + credit hoàn (kiểm tra `/me` trước/sau) — EC-S3-2 có integration test
- [ ] Credit race EC-S3-1: test song song 2 request khi còn 1 lượt → đúng 1 pass
- [ ] Benchmark 50 ảnh calibration: so score/explanation 2 provider vs chấm tay; cost đo thật ≤ $0.01/ảnh (Validation ADR-0004)
- [ ] IAP sandbox: mua premium (sandbox 2 store hoặc RevenueCat sandbox) → `/me` trả premium, review không giới hạn; hết hạn → về free (EC-S3-9)
- [ ] Sync roundtrip: chụp offline (airplane) → bật mạng + login → history lên server; login thiết bị thứ hai → thấy metadata + score (ảnh placeholder); conflict test EC-S3-6
- [ ] DELETE /me: xoá sạch server-side (DB + GCS), local giữ nguyên — EC-S3-11
- [ ] Offline degrade: server tắt hoàn toàn → camera, coaching, capture, score offline hoạt động bình thường (airplane mode test — Validation ADR-0002)
- [ ] Security audit pass theo `.claude/rules/security.md` (artifact bắt buộc trước beta — Rule 9); không secrets trong diff
- [ ] Rate limit: vượt ngưỡng Rule 8 → 429 (test tự động cho magic-link)
- [ ] `npm run build` + `npm test` pass (backend); `flutter analyze` 0 issue + `flutter test` pass (app); Prisma dùng migrate, không db push
- [ ] Beta build: TestFlight + Play Internal có build submitted **trước 2026-08-11** (chừa thời gian store review); nếu Rule 10 cắt iOS → Play Internal only + ghi nhận vào roadmap
- [ ] Crashlytics + Analytics nhận event từ build beta (FR-S3-8)

---

## Open Questions

- [ ] **Giá Premium** (PRD Open Question): khảo giá competitor, đề xuất $4.99/tháng hoặc VND-adjusted — **chốt trước khi submit store** (giữa sprint).
- [ ] **RevenueCat account + webhook secret**: tạo trước sprint cùng GCP project / store accounts (dependency roadmap). Nếu đổi sang IAP native trực tiếp → cần ADR mới (Rule 3 assumption).
- [ ] **macOS host cho iOS build**: máy dev là Windows — dùng GitHub Actions `macos` runner + Fastlane cho FR-S3-9 và TestFlight, hay mượn máy Mac? Ảnh hưởng trực tiếp khả năng giữ FR-S3-9 trong scope. **Chốt trước 2026-08-04.**
- [ ] **Ngày credit theo UTC** (Rule 2) lệch với ngày local của counter offline — chấp nhận ở beta hay đổi theo timezone user (`/me` nhận header timezone)? Khởi điểm: UTC cho đơn giản, đo phàn nàn thực tế.
- [ ] **Reference device iOS**: iPhone 12 theo PRD — có máy thật để đo gate FR-S3-9 chưa?

---

## Implementation Notes & Known Deviations (2026-07-07)

Backend core + Android-first app wiring đã implement (swarm). Backend: build 0 lỗi · 61 unit test pass · lint 0. App: `flutter analyze` 0 · `flutter test` 132/132. Sau adversarial review (correctness + security), các fix đã áp: sync cross-user photo read (CWE-639), premium mua giữa ngày bị chặn (EC-S3-3), refund cùng transaction với status=failed (Rule 2), ValidationPipe trả 422.

**Còn nợ trước beta gate (Rule 9) — chưa implement trong lần chạy này:**

| # | Hạng mục | Vì sao hoãn | Cần làm |
|---|----------|-------------|---------|
| D1 | **Rate limiting Rule 8** (per-email magic-link 3/15p, per-user 60/p, review 10/p) — mới chỉ có global 300/p/IP | Cần Redis-backed throttler (`@nestjs/throttler` + Redis store); Redis chưa chạy local (không có Docker) | Thêm throttler keyed theo email/userId + test tự động (acceptance criteria) |
| D2 | **Worker tách service riêng** (`src/main.worker.ts`) | Hiện worker BullMQ chạy in-process cùng API qua `OnModuleInit` — API scale-to-zero sẽ ngừng consume | Tách entry worker + `start:worker` script + Dockerfile target (tech-strategy: api/worker riêng service) |
| D3 | **`GET /photos?cursor`** pull đặt ở `/sync/photos` (tránh nhầm collision với PhotosController) | Quyết định swarm; thực ra `/photos` literal không va `/photos/:id` | Chuyển về `GET /photos` đúng spec HOẶC ghi ADR chấp nhận `/sync/photos` |
| D4 | **RevenueCat webhook DTO** là plain interface → bỏ qua ValidationPipe | Payload RC nhiều field không quan tâm; handler đã optional-chain phòng thủ | Đổi sang class-DTO hoặc zod parse (spec Security: validate webhook payload) |
| D5 | **Storage thật (GCS/minio)** — `getObjectBase64`/`deletePrefix` throw 503 | Không cài cloud SDK lần này (constraint) | Wire `@google-cloud/storage` V4 signed URL; KHÔNG dùng lại JWT_SECRET làm HMAC key (L2) |
| D6 | **pino + PII redact** (FR-S3-8), **@fastify/helmet** (M1) | Ngoài scope core lần này | Thêm trước beta |
| D7 | **Integration test cần DB live** (EC-S3-1 race, EC-S3-2 refund, auth e2e) | Docker/Postgres/Redis không chạy được trên máy dev lần này | Chạy `docker compose up` rồi `prisma migrate dev` + viết integration test |
| D8 | **iOS native module** (FR-S3-9), **RevenueCat SDK app + paywall thật** (FR-S3-5 app), **image resize isolate**, **Firebase** | Cần macOS host / store accounts / ngoài scope core | Theo Rule 10 thứ tự |

**Môi trường:** backend cần **Node ≥ 20** (dùng Node 24 qua nvm; Node 16 mặc định KHÔNG chạy được NestJS 11). Prisma pin **v6** (v7 breaking). Flutter ở `F:\flutter`. Migration SQL sinh offline ở `prisma/migrations/20260706000000_sprint3_init/` (chưa apply — cần DB).

## Version History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-07-06 | Đạt Trần | Initial — sinh từ PRD FR-8..12 + ADR-0002/0004 + System Design §3/§5/§6/§7 + roadmap Phase 3; khớp scaffold `backend/` hiện có. Assumptions đánh dấu inline: 2 pool credit riêng, RevenueCat, flutter_secure_storage, con số rate limit |
| 1.1 | 2026-07-07 | Đạt Trần (swarm) | Backend core + Android app wiring implemented; adversarial review + fixes; Implementation Notes + D1–D8 deviations ghi lại |
