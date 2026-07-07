# Feature Specification: Sprint 4 — Beta Hardening + Deploy + Launch

<!--
Feature Specification
Filename: docs/specs/spec-sprint-4.md
Owner: Builder (/builder)
Handoff to: Builder (/builder), QA Engineer (/qa-engineer), Security Auditor (/security-auditor)
Purpose: Dev đọc và implement. QA đọc và test. Không cho phép mơ hồ.
-->

## Metadata

**Status:** Draft — chờ approve
**Author:** Đạt Trần
**Date:** 2026-07-07
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) (NFR-3 privacy, NFR-7 review latency, NFR-8 cost; beta launch goals)
**Related ADR:** [0002](../adr/0002-offline-first-backend-sprint-3.md), [0004](../adr/0004-cloud-ai-provider-adapter.md) (benchmark calibration), [0007](../adr/0007-native-owns-camera-session.md) (iOS port)
**Related design:** [system-design-shotmate.md](../design/system-design-shotmate.md) §7 Security, §8 Scalability
**Related spec:** [spec-sprint-3.md](spec-sprint-3.md) — **nguồn gốc trực tiếp của sprint này**: toàn bộ Business Rules + API contract Sprint 3 tiếp tục hiệu lực; Sprint 4 trả nợ D1–D8 và đưa hệ thống ra beta

---

## Overview

Sprint 3 đã implement xong **code core** (backend NestJS đầy đủ modules, app Android wiring auth/review/settings — backend 61 test, app 132 test, cả hai gate xanh) nhưng hệ thống **chưa từng chạy thật**: storage stub trả 503, rate limit mới có tầng IP global, worker chạy in-process với API, chưa có integration test trên DB live. Sprint 4 **không thêm feature mới** — biến code thành hệ thống production-ready cho **beta Android-only**:

1. **Trả nợ D1–D7** của spec-sprint-3 (rate limit, tách worker, storage thật, webhook validation, observability, integration test)
2. **Nợ Sprint 2 còn lại**: accuracy scene classifier + user test hint (FR-S4-10)
3. **Beta launch Android-only**: security audit, benchmark calibration, store submit, 50 testers (FR-S4-11)

> **iOS cắt khỏi phạm vi Sprint 4 hoàn toàn** (quyết định 2026-07-07 — không còn là "cắt nếu trễ", mà cắt ngay từ đầu). Lý do: không có macOS host + iPhone 12 reference device sẵn sàng trong sprint này. Beta launch **Android-only qua Play Internal**; TestFlight/iOS dời sang phase riêng sau beta (roadmap Phase 5, khi có thiết bị/host). FR-S4-8 (native module iOS) không nằm trong deliverable sprint này.
>
> **Deploy GCP thật (Cloud Run/Cloud SQL/Memorystore) cũng ngoài phạm vi thực thi sprint này** — môi trường triển khai không có `gcloud`/credentials/GCP project. Phần này được làm **deploy-ready** (Dockerfile 2-target api/worker, CI workflow, migration script) nhưng chạy `gcloud`/tạo project/deploy thật do chủ dự án tự thực hiện khi có GCP project + billing thật.

**Điểm xuất phát (2026-07-07):** commit `5c77b9d` — backend build 0 lỗi, lint 0, 61/61 unit test; app analyze 0, 132/132 test. Deviations D1–D8 ghi trong spec-sprint-3 §Implementation Notes.

---

## Business Rules

### Rule 0 — Kế thừa Sprint 1–3 nguyên vẹn

Business Rules Sprint 1–3 áp dụng đầy đủ, đặc biệt: offline-first bất khả xâm phạm (S3 Rule 1), credit atomic server-side (S3 Rule 2), không tin client về subscription (S3 Rule 3), rate limit S3 Rule 8 — **Sprint 4 phải enforce đầy đủ những rule mà Sprint 3 mới enforce một phần**. Không thay đổi bất kỳ hành vi realtime nào; frame→hint <100ms p90 là regression gate mọi thay đổi app.

### Rule 1 — Deploy trước, hardening theo

Môi trường **dev trên Cloud Run phải sống trước giữa sprint** (api + worker + Cloud SQL + Memorystore + GCS). Lý do: toàn bộ acceptance criteria Sprint 3 chưa verify được vì thiếu DB/Redis/storage thật — mọi hạng mục hardening (D1, D5, D7) cần môi trường này để chứng minh. Local: docker compose (`infra/docker-compose.yml`) là môi trường integration test bắt buộc chạy được.

### Rule 2 — Beta gate là điều kiện dừng (kế thừa S3 Rule 9, giờ đo thật)

Trước khi mời tester ngoài, **tất cả** phải pass — không đàm phán:

- [ ] Security audit theo `.claude/rules/security.md` (artifact bắt buộc, /security-auditor)
- [ ] Crash-free > 99.5% trong internal testing ≥ 3 ngày
- [ ] Benchmark 50 ảnh calibration (Validation ADR-0004) + cost đo thật ≤ $0.01/ảnh
- [ ] Rate limiting đầy đủ Rule 8 Sprint 3 (D1 đã trả)
- [ ] Integration test EC-S3-1 (credit race) + EC-S3-2 (refund) pass trên DB live
- [ ] Offline degrade test (airplane mode) pass trên build beta

### Rule 3 — Thứ tự cắt scope nếu trễ (quyết định trước, không đàm phán giữa sprint)

> iOS đã cắt khỏi sprint này ngay từ đầu (không phải "cắt nếu trễ" — xem Overview). Danh sách dưới áp dụng cho phần còn lại nếu vẫn trễ:

1. **Cắt trước:** User test hint overload (FR-S4-10b) → thay bằng feedback beta testers tuần đầu.
2. **Cắt nhì:** Test set accuracy scene giảm 150 → 60 ảnh (vẫn đủ 20/scene để có tín hiệu).
3. **Cắt ba:** Observability nâng cao (OTel trace, Cloud Monitoring alert trong FR-S4-6) → giữ lại pino + helmet (bắt buộc bảo mật), dời phần trace/alert.
4. **Không bao giờ cắt:** rate limiting (FR-S4-4), storage thật (FR-S4-3), security audit, integration test credit race (FR-S4-7).

### Rule 4 — Hạ tầng theo tech-strategy, không tự chế

Mọi lựa chọn hạ tầng đã chốt trong `.claude/rules/tech-strategy.md` (Cloud Run, Cloud SQL, Memorystore, GCS + CDN, Secret Manager, GitHub Actions, Fastlane). Deviation cần ADR mới. Migration qua `prisma migrate deploy` — **không** `db push` lên bất kỳ môi trường chung nào.

---

## Functional Requirements

### FR-S4-1: Hạ tầng GCP + CI/CD — chuẩn bị deploy-ready (KHÔNG tự deploy thật)

> Môi trường thực thi sprint này không có `gcloud`/GCP project/credentials. Deliverable là **code + config sẵn sàng chạy** khi chủ dự án có GCP project thật — không phải hạ tầng đã lên production.

- **Dockerfile** multi-stage 2 target (`api`, `worker` — khớp FR-S4-2) trong `backend/Dockerfile`.
- **GitHub Actions** (`infra/github-actions/ci.yml` mở rộng): job build Docker image cho cả 2 target; job deploy Cloud Run **để sẵn, gated sau `if: false` hoặc `workflow_dispatch` thủ công** cho tới khi có GCP project + OIDC secret thật — không chạy tự động trong sprint này.
- **Migration**: script/README hướng dẫn `prisma migrate deploy` khi có `DATABASE_URL` production — không tự chạy vì không có Cloud SQL thật.
- Tài liệu hoá trong `infra/DEPLOY.md` (mới): danh sách biến Secret Manager cần tạo (`DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `SMTP_*`, `REVENUECAT_WEBHOOK_SECRET`), lệnh `gcloud run deploy` mẫu cho cả 2 service, cấu hình min-instances (api 0, worker 1 — EC-S4-2) — để chủ dự án chạy tay khi sẵn sàng.

### FR-S4-2: Tách worker service riêng (trả nợ D2)

Hiện worker BullMQ chạy in-process cùng API qua `OnModuleInit` — API scale-to-zero sẽ ngừng consume job. Cần:

- Entry riêng `backend/src/main.worker.ts`: bootstrap Nest application context (không HTTP) + processor `ai-review` + repeatable job `token-cleanup`.
- `package.json`: script `start:worker`; Dockerfile multi-stage 2 target (api/worker) hoặc 1 image + command override.
- API **không** khởi động processor nữa (chỉ enqueue). Health check worker: liveness qua BullMQ heartbeat/log.

### FR-S4-3: Storage thật — GCS + minio (trả nợ D5)

`StorageService` hiện throw 503 `STORAGE_UNAVAILABLE`. Implement 2 driver sau interface hiện có, chọn theo env:

- **GCS** (prod/dev cloud): `@google-cloud/storage`, V4 signed URL PUT (TTL 15 phút, `image/jpeg` only, `X-Goog-Content-Length-Range` 0–10MB); `getObjectBase64` cho worker; `deletePrefix` cho DELETE /me.
- **minio** (local): S3-compatible client, cùng contract, cho integration test không cần GCP.
- Ký URL bằng service account key/HMAC key **riêng** — KHÔNG dùng lại `JWT_SECRET` (finding L2 review Sprint 3).

### FR-S4-4: Rate limiting đầy đủ (trả nợ D1)

Implement đủ bảng S3 Rule 8 (hiện mới có global 300/phút/IP):

| Scope | Limit | Key |
|-------|-------|-----|
| `POST /auth/magic-link` | 3/email/15 phút **và** 10/IP/giờ | email (normalize lowercase) + IP |
| `POST /photos/:id/review` | 10/user/phút | userId từ JWT |
| Toàn API authenticated | 60 req/phút/user | userId |
| Toàn API | 300 req/phút/IP (giữ nguyên) | IP |

- Backing store: **Redis** (đã có cho BullMQ) — counter TTL theo window; KHÔNG in-memory (Cloud Run nhiều instance).
- Vượt → 429 `RATE_LIMITED` theo error envelope chuẩn. Test tự động cho magic-link (acceptance Sprint 3 còn nợ).
- Redis chết → xử lý theo EC-S4-1.

### FR-S4-5: Chốt 2 deviation API (trả nợ D3 + D4)

- **D3:** Chuyển `GET /sync/photos` → **`GET /photos`** trên PhotosController, đúng bảng API spec-sprint-3 (route literal `/photos` không va `/photos/:id/review`). SyncController chỉ giữ `POST /sync`. App đổi 1 đường dẫn trong repository tương ứng. Không cần ADR (trở về đúng spec đã approve).
- **D4:** Webhook RevenueCat: thay plain interface bằng **zod parse** payload (spec Security S3: validate webhook payload) — field không nhận diện được → bỏ qua, thiếu field bắt buộc (`type`, `app_user_id`) → 422, log cảnh báo. Giữ so sánh secret constant-time.

### FR-S4-6: Observability backend (trả nợ D6)

- **pino** structured JSON qua `nestjs-pino` + Fastify: `redact` email (PII duy nhất), KHÔNG log token/JWT/base64 ảnh. Request-id correlation.
- **@fastify/helmet** (finding M1 review Sprint 3).
- **OpenTelemetry** OTLP → Cloud Trace: span API → queue → provider (đo NFR-7 <10s p90 bằng trace thật).
- Alert (Cloud Monitoring): error rate > 5%, queue depth > 100, provider failure rate > 20%, worker im lặng > 5 phút.

### FR-S4-7: Integration test trên DB live (trả nợ D7)

Chạy trên docker compose (postgres + redis + minio + mailpit), CI job riêng với services:

- **EC-S3-1**: 2 request review song song khi còn 1 credit → đúng 1 pass (transaction atomic).
- **EC-S3-2**: 2 provider fail hết retry → `status=failed` + credit hoàn trong cùng transaction.
- **Auth e2e**: magic-link → mailpit → verify → refresh → reuse detection revoke family (EC-S3-5).
- **Sync roundtrip + conflict** (EC-S3-6): upsert theo UUID, LWW theo `taken_at`, `conflicts[]` trả bản thắng.
- **DELETE /me** (EC-S3-11): cascade DB + xoá prefix minio + revoke token.

### FR-S4-8: iOS native inference module — **NGOÀI PHẠM VI sprint này**

Cắt khỏi Sprint 4 hoàn toàn (xem Overview). Không có deliverable code Swift/iOS trong sprint này. Khi resource sẵn sàng (macOS host + iPhone 12 reference), việc port module Android sang Swift theo contract [`app/ios/NATIVE_MODULE.md`](../../app/ios/NATIVE_MODULE.md) sẽ được lập spec riêng trong phase hậu-beta (roadmap Phase 5).

### FR-S4-9: App — monetization + observability thật (trả nợ D8 app-side)

- **RevenueCat**: `purchases_flutter` + `PaywallScreen` thật (1 gói tháng, giá từ store), điểm vào: CTA 402 hết credit + Settings. Backend webhook đã sẵn (FR-S3-5). **Public SDK key đã có** (project RevenueCat của Đạt, key `test_...`, dùng chung cho Android/iOS ở giai đoạn sandbox) — lưu ở `app/dart_defines.local.json` (gitignored, copy từ `dart_defines.example.json`), build với `flutter run --dart-define-from-file=dart_defines.local.json`. Sandbox purchase test thật vẫn cần **Play Console product** (`monthly`) đã tạo và map trong RevenueCat Offerings trước khi `loadOffer()` trả về gói — chưa có product = `getOfferings()` trả rỗng, UI hiển thị "chưa có gói".
- **Image resize isolate**: resize ≤1568px cạnh dài JPEG q85 chạy trong isolate (package `image`) — hiện resize đang thiếu/chạy thread chính; đo <4s cho ảnh 12MP trên reference device.
- **Firebase**: `flutterfire configure` (nợ từ Sprint 1 §2.4) — Crashlytics + Analytics với toàn bộ events đã liệt kê spec 1–3 (`login_completed`, `review_requested`, `review_completed{provider, latencyMs}`, `review_failed`, `paywall_shown`, `purchase_completed`, `sync_completed{count}` + events camera/score Sprint 1–2). **Cần Firebase project + `google-services.json` thật** để hoạt động — code init làm trong sprint này, chạy thật khi có project.
- **Fastlane** lane `beta`: build + upload **Play Internal only** (Android-only beta — không có TestFlight lane trong sprint này).

### FR-S4-10: Nợ Sprint 2 — accuracy + UX

- **a) Accuracy scene classifier ≥ 85%** (S2 Rule 8): gom test set **150 ảnh** (50 landscape / 50 portrait / 50 food — đa dạng ánh sáng/bối cảnh), chạy qua pipeline classifier (ML Kit labeling + mapping hiện có), đo accuracy + confusion matrix. < 85% → kích hoạt đường thoát ADR-0006: spike train TFLite classifier 3 lớp (timebox 3 ngày, quyết định go/no-go trong sprint).
- **b) User test hint overload** (S2 risk): 5 người dùng nội bộ, mỗi người 10 phút chụp tự do, đo: số hint hiển thị/phút, % hint được làm theo, cảm nhận "rối/hữu ích" (thang 5). Rối > 2/5 trung bình → giảm max hint 2 → 1 qua Remote Config trước beta.

### FR-S4-11: Beta launch

- Store listing (screenshots, mô tả 2 ngôn ngữ Việt/Anh), **privacy label** khớp thực tế: ảnh chỉ upload opt-in, analytics events, email.
- Privacy policy page (host tĩnh — GCS + CDN đủ).
- Submit build: TestFlight + Play Internal **trước khi hết tuần 1 của sprint** (chừa thời gian store review; nếu Rule 3 cắt iOS → Play Internal only, ghi nhận vào roadmap).
- Tuyển **50 beta testers** (kênh: bạn bè/cộng đồng nhiếp ảnh/khoa CNTT), form đăng ký + onboarding note.
- Vòng lặp feedback: weekly changelog (Communication Plan roadmap) + form feedback + `POST /feedback` in-app (FR-S3-10 đã có backend).

---

## API Changes

Không endpoint mới. Hai thay đổi so với trạng thái code hiện tại (đều là **trở về đúng** bảng API spec-sprint-3):

| Thay đổi | Từ | Thành |
|----------|-----|-------|
| D3 | `GET /sync/photos?cursor&limit` | `GET /photos?cursor&limit` (PhotosController) |
| D4 | Webhook RC nhận payload không validate | zod parse — thiếu field bắt buộc → 422 |

Error envelope, mã lỗi, rate limit response (429 `RATE_LIMITED`) giữ nguyên spec-sprint-3.

**Platform channels:** không đổi contract — FR-S4-8 chỉ port iOS lên cùng payload schemaVersion 2.

---

## Database Changes

**Không đổi schema** (server lẫn Drift). Việc DB duy nhất: apply migration `20260706000000_sprint3_init` lên Cloud SQL dev/staging/prod qua `prisma migrate deploy` trong CI (FR-S4-1). Cron `token-cleanup` (BullMQ repeatable) chuyển sang chạy ở worker service (FR-S4-2).

---

## Security Requirements

Kế thừa đầy đủ bảng Security spec-sprint-3. Điểm enforce **mới/hoàn thiện** trong sprint này:

| Yêu cầu | Implement |
|---------|-----------|
| Rate limit đầy đủ (CWE-307/770) | FR-S4-4 — Redis-backed, keyed email/user/IP |
| HTTP hardening | @fastify/helmet (FR-S4-6) |
| PII trong log | pino redact email; không token/ảnh trong log (FR-S4-6) |
| Webhook validation (CWE-20) | zod parse payload RevenueCat (FR-S4-5) |
| Khoá ký storage riêng | KHÔNG dùng JWT_SECRET làm HMAC key (FR-S4-3, finding L2) |
| Secrets prod | GCP Secret Manager + GitHub OIDC — không key file trong repo/CI log (FR-S4-1, khi deploy thật) |
| Bucket private | GCS uniform access, không public ACL; đọc qua signed URL ngắn hạn |
| Audit trail | Log structured credit trừ/hoàn + subscription change — giờ có pino để làm thật |

**Security audit toàn backend** (/security-auditor hoặc `/security-review`) là artifact bắt buộc của beta gate (Rule 2) — chạy sau khi D1–D6 trả xong, trước khi mời tester.

---

## Caching Impact

Không đổi so với Sprint 3: không cache credit; Remote Config cache 5 phút; `/me` cache per-session phía app. **Mới:** counter rate-limit trên Redis (TTL theo window — FR-S4-4).

---

## Frontend Changes (Flutter)

Không route mới ngoài những gì Sprint 3 đã khai (`/login`, `/auth/verify`, `/paywall`). Sprint 4 làm `PaywallScreen` **thật** (RevenueCat SDK thay placeholder), resize isolate, Firebase init trong `main.dart` (guard flavor dev không gửi analytics). Provider mới duy nhất: `purchasesProvider` wrap RevenueCat SDK (đã dự kiến `subscriptionProvider` trong spec-sprint-3 — dùng đúng tên đó).

**Dependencies mới (pubspec):** `purchases_flutter`, `image`, `firebase_core`, `firebase_analytics`, `firebase_crashlytics` (các gói còn lại — `flutter_secure_storage`, `app_links`, `dio` — đã có từ Sprint 3).

---

## Event / Job Changes

| Loại | Chi tiết |
|------|----------|
| BullMQ `ai-review` | Không đổi contract — chuyển consumer sang worker service (FR-S4-2) |
| BullMQ `token-cleanup` | Chạy ở worker service, repeatable 1 lần/ngày |
| Firebase Analytics | Toàn bộ events spec 1–3 — code sẵn sàng, bắn thật khi có Firebase project (FR-S4-9) |
| Cloud Monitoring alerts | 4 alert FR-S4-6 — cấu hình ghi trong `infra/DEPLOY.md`, kích hoạt khi deploy thật |

---

## Non-Functional Requirements

Bảng Performance spec-sprint-3 giữ nguyên. Trong sprint này đo được trên **docker compose local** (chưa có Cloud Run thật — cột "Đo bằng" ghi rõ môi trường):

| Operation | Target | Đo bằng |
|-----------|--------|---------|
| Cloud review end-to-end | < 10s p90 (NFR-7) | Đo trên docker compose local (≥ 20 lần) khi có API key thật; OTel trace khi deploy thật |
| API non-AI | < 300ms p95 | Đo local; Cloud Monitoring khi deploy thật |
| Resize + upload 12MP (client) | < 4s | manual trên reference device Android |
| Cost/ảnh review | ≤ $0.01 (NFR-8) | benchmark 50 ảnh — cần API key thật (xem hướng dẫn lấy key) |
| Frame→hint Android (regression) | < 100ms p90 — không được chậm đi | Perf HUD trước/sau mọi thay đổi app |
| Crash-free internal | > 99.5% ≥ 3 ngày | Crashlytics — cần Firebase project thật |

---

## Edge Cases

### EC-S4-1: Redis chết → rate limiter mất backing store
**Expected:** Fail-open cho traffic authenticated (không chặn user thật vì hạ tầng mình lỗi) nhưng **giữ** global IP limit in-memory per-instance làm lưới cuối; log ERROR + alert. Review enqueue vẫn trả 503 `REVIEW_UNAVAILABLE` (hành vi Sprint 3 — BullMQ cần Redis).

### EC-S4-2: Worker scale-to-zero bỏ đói queue
**Condition:** Cloud Run worker min-instances 0, không có HTTP traffic đánh thức.
**Expected:** Worker đặt **min-instances 1** ở beta (chi phí ~vài $/tháng, chấp nhận). Job nằm queue khi worker chết giữa chừng → BullMQ retry/stalled-check nhặt lại, không mất job.

### EC-S4-4: Store review từ chối / yêu cầu sửa
**Expected:** Submit trong tuần 1 (FR-S4-11) chừa ≥ 1 tuần re-submit. Rủi ro biết trước: quyền camera (mô tả rõ mục đích), account deletion (đã có DELETE /me — 5.1.1(v)), privacy label khớp thực tế opt-in upload.

### EC-S4-5: RevenueCat sandbox entitlement lệch production
**Expected:** Test sandbox Play Store xác nhận flow (purchase → webhook → `/me` premium) khi có RevenueCat account + Play Console product thật; trước launch công khai chạy 1 giao dịch thật (tự mua) xác nhận production key/entitlement. Webhook trễ → app fallback `POST /subscriptions/verify` (đã có Sprint 3).

### EC-S4-6: Migration fail trên Cloud SQL (lần apply đầu, khi deploy thật)
**Expected:** `prisma migrate deploy` chạy như bước CI riêng **trước** deploy revision mới; fail → deploy dừng, revision cũ giữ nguyên. Không sửa tay DB; sửa migration qua PR mới. (Ngoài scope thực thi sprint này — ghi nhận cho lúc chủ dự án deploy thật.)

### EC-S4-7: Test set accuracy không đạt 85% (FR-S4-10a)
**Expected:** Kích hoạt đường thoát ADR-0006 (spike TFLite 3 lớp, timebox 3 ngày). Spike fail → hạ ngưỡng confidence hiển thị zoom suggestion (ít suggest hơn nhưng đúng hơn) + ghi vào roadmap là known limitation của beta — không chặn launch.

---

## Acceptance Criteria

> Backend verify trên **docker compose local** (integration test) — Cloud Run dev là bước riêng do chủ dự án chạy sau khi có GCP project (FR-S4-1). App verify trên Android reference device. iOS ngoài phạm vi sprint này.

**Hạ tầng + nợ backend (verify local qua docker compose):**
- [ ] Worker tách entry riêng (`main.worker.ts`); job enqueue từ api được worker process (không phải api process) consume — kill api process, job vẫn chạy (FR-S4-2)
- [ ] Upload e2e qua minio: signed URL → PUT ảnh → worker/DELETE đọc được qua interface `IStorageService` (FR-S4-3)
- [ ] Rate limit: test tự động magic-link (3/email/15p → 429) + review (10/user/p → 429) trên Redis local; Redis down → fail-open có log (FR-S4-4, EC-S4-1)
- [ ] `GET /photos` hoạt động đúng spec-sprint-3 (cursor, max 100); route `/sync/photos` đã xoá (FR-S4-5)
- [ ] Webhook RC: payload thiếu field bắt buộc → 422 (zod); payload hợp lệ → Subscription upsert (FR-S4-5)
- [ ] pino log có redact email, không có token/ảnh; helmet headers hiện diện trong response (FR-S4-6)
- [ ] Integration suite FR-S4-7 pass trên docker compose **và** trong CI (EC-S3-1, EC-S3-2, auth e2e, sync conflict, DELETE /me)
- [ ] Dockerfile 2-target (api/worker) build thành công local (`docker build --target api`, `--target worker`); `infra/DEPLOY.md` viết xong (FR-S4-1)

**App:**
- [x] RevenueCat SDK + PaywallScreen wiring xong (code); Public SDK key thật đã cấu hình (`app/dart_defines.local.json`); sandbox purchase test thật vẫn chờ Play Console product `monthly` (FR-S4-9, EC-S4-5)
- [ ] Resize 12MP < 4s trong isolate, UI không giật (FR-S4-9)
- [ ] Firebase init code xong; Crashlytics/Analytics bắn thật khi có project (FR-S4-9)
- [ ] Android frame→hint p90 không regression (đo Perf HUD trước/sau sprint)

**Chất lượng + beta:**
- [ ] Accuracy scene ≥ 85% trên test set 150 ảnh, có confusion matrix lưu docs (FR-S4-10a, EC-S4-7)
- [ ] User test 5 người hoàn thành, kết quả + quyết định max-hint ghi lại (FR-S4-10b)
- [ ] Benchmark 50 ảnh calibration: score 2 provider vs chấm tay + cost ≤ $0.01/ảnh — cần API key thật (Validation ADR-0004)
- [ ] Security audit artifact pass (Rule 2); không secrets trong diff
- [ ] Build submitted **Play Internal** trong tuần 1; ≥ 50 testers được mời; crash-free > 99.5% ≥ 3 ngày trước khi mời tester ngoài
- [ ] `npm run build` + `npm test` + lint pass; `flutter analyze` 0 + `flutter test` pass; toàn bộ gate xanh trên CI

---

## Implementation Notes (2026-07-07)

Toàn bộ FR-S4-2..7, FR-S4-9 đã implement (swarm, 4 worker song song cho D1/D4/D5/D6 + orchestrator cho D2/D3/D7/FR-S4-1/app wiring). Kết quả cuối:

- **Backend:** `npm run build` 0 lỗi · `npm run lint` 0 issue · **87/87 unit test** · **13/13 integration test** (`npm run test:integration` trên docker compose local: 4 test storage/minio D5 + 9 test D7 mới — credit race EC-S3-1, refund EC-S3-2, auth e2e đầy đủ magic-link→mailpit→verify→refresh rotation→reuse detection EC-S3-5, sync conflict LWW EC-S3-6, DELETE /me EC-S3-11).
- **App:** `flutter analyze` 0 issue · **139/139 test** (132 gốc + 7 mới cho resize isolate). RevenueCat Public SDK key thật đã cấu hình (`app/dart_defines.local.json`, gitignored — copy từ `app/dart_defines.example.json`).
- **Bug hạ tầng test phát hiện qua D7** (không phải do code Sprint 4 gây ra — tồn tại tiềm ẩn từ Sprint 3, chỉ lộ ra khi bootstrap toàn bộ `AppModule` thật lần đầu): Vitest dùng esbuild để transform TypeScript, và esbuild **không thể emit `design:paramtypes` decorator metadata** (transpile-only, không có type info) — NestJS DI container cần metadata này để resolve constructor param. Mọi unit test trước đó né được vì chúng `new` service trực tiếp thay vì bootstrap qua `NestFactory`. Fix: thêm `unplugin-swc` + `.swcrc` (`legacyDecorator` + `decoratorMetadata`) vào cả `vitest.config.ts` và `vitest.integration.config.ts` — đây là giải pháp chính thức NestJS khuyến nghị cho Vitest.
- **4 module thiếu `ConfigModule` tường minh** (`AuthModule`, `UsersModule`, `PhotosModule`, `AiReviewModule` dùng `ConfigService` qua provider nhưng không khai trong `imports`) — dựa hoàn toàn vào `isGlobal: true`. Đây không phải nguyên nhân gây lỗi DI (đã thử thêm rồi revert khi xác nhận không phải nguyên nhân — global module không cần import tường minh trong NestJS, và tự ý thêm `imports: [ConfigModule]` không `.forRoot()` còn tạo ra module rỗng che mất `ConfigService` global thật). Giữ nguyên code gốc, không đổi.
- **Deviations resolved:** D1 (rate limit Redis-backed 4 tầng, guard + service riêng), D2 (`main.worker.ts`/`WorkerModule` tách biệt hoàn toàn khỏi API, verify qua integration test kill-api-job-vẫn-chạy), D3 (`GET /photos` đúng spec, `/sync/photos` xoá), D4 (zod validate webhook RC), D5 (`@aws-sdk/client-s3` + minio, HMAC key riêng khỏi JWT_SECRET — finding L2 đã fix), D6 (pino redact + helmet, verify curl thật), D7 (integration suite trên DB/Redis/mailpit/minio thật).
- **FR-S4-1** hoàn thành đúng scope đã thu hẹp: `Dockerfile` 2-target (`api`/`worker`), `infra/DEPLOY.md` (hướng dẫn `gcloud` đầy đủ, chưa chạy), CI job `docker-image` build-only (không push/deploy).

**Còn nợ trước beta gate (Rule 2) — ngoài phạm vi thực thi, cần chủ dự án tự làm:**

| # | Hạng mục | Vì sao hoãn | Cần làm |
|---|----------|-------------|---------|
| E1 | Deploy Cloud Run thật | Không có GCP project/gcloud credentials trong môi trường | Theo `infra/DEPLOY.md`, cần GCP project + billing |
| E2 | Sandbox purchase RevenueCat thật | Chưa có Play Console product `monthly` map vào Offering | Tạo product trong Play Console + gắn Offering RevenueCat dashboard |
| E3 | Firebase Analytics/Crashlytics thật | Chưa có Firebase project + `google-services.json` | `flutterfire configure` sau khi tạo Firebase project |
| E4 | Benchmark 50 ảnh + cost thật ≤$0.01/ảnh | Cần `ANTHROPIC_API_KEY`/`GEMINI_API_KEY` thật với billing | Điền key vào `backend/.env`, chạy benchmark theo ADR-0004 |
| E5 | Accuracy scene 150 ảnh, user test 5 người (FR-S4-10) | Cần gom ảnh thật + người test — ngoài phạm vi code | Theo kế hoạch FR-S4-10 |
| E6 | Security audit chính thức | Cần chạy `/security-review` như artifact riêng trước beta gate | Chạy sau khi có môi trường deploy thật |

---

## Open Questions

- [ ] **Giá Premium** (carry): chốt trước khi submit store tuần 1 — đề xuất $4.99/tháng hoặc VND-adjusted (49.000đ), khảo giá competitor trong 1 buổi.
- [ ] **Ngày credit UTC vs local** (carry): giữ UTC ở beta, đo phàn nàn thật — chỉ mở lại nếu ≥ 3 tester phàn nàn.
- [ ] **Kênh tuyển 50 testers**: nhóm nhiếp ảnh FB/Discord nào? Cần danh sách trước tuần 2.
- [ ] **Budget hạ tầng beta/tháng**: ước Cloud Run + Cloud SQL (db-f1-micro) + Memorystore (1GB) + AI cost 50 users ≈ $40–70/tháng — xác nhận chấp nhận được khi deploy thật.
- [ ] **iOS/TestFlight**: lập spec riêng cho phase hậu-beta khi có macOS host + iPhone 12 (không còn là open question chặn sprint này — đã cắt hẳn).

---

## Version History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-07-07 | Đạt Trần | Initial — sinh từ spec-sprint-3 Implementation Notes (deviations D1–D8) + nợ Sprint 2 (accuracy scene, user test, iOS module) + roadmap Phase 3 beta goals. Quyết định inline: D3 trở về `GET /photos`, worker min-instances 1, rate limiter fail-open khi Redis chết |
| 1.1 | 2026-07-07 | Đạt Trần (swarm) | **Cắt iOS hoàn toàn khỏi scope** (không macOS host/iPhone 12 sẵn sàng) — beta Android-only, FR-S4-8 dời sang phase riêng hậu-beta. **Deploy GCP thật ngoài phạm vi thực thi** (không có gcloud/credentials trong môi trường) — FR-S4-1 đổi thành chuẩn bị deploy-ready (Dockerfile, CI gated, `infra/DEPLOY.md`). Acceptance criteria cập nhật để verify được trên docker compose local. |
