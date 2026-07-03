# Tech Strategy - Golden Paths (ShotMate)

This is the **SINGLE SOURCE OF TRUTH** for technology choices in ShotMate.

## Compliance

1. **Follow This File**: Use the technologies listed in the Golden Paths below
2. **No Deviations**: Do not suggest alternatives unless explicitly instructed; deviations require an ADR
3. **Latest Stable**: Always use the latest stable version unless pinned

## Mobile Golden Path (Flutter)

| Component | Choice |
|-----------|--------|
| Framework | Flutter (latest stable) |
| State Management | Riverpod |
| Routing | GoRouter |
| Models/Immutability | Freezed + json_serializable |
| HTTP Client | Dio |
| Local Storage | **Drift** (SQLite) — NOT Isar (unmaintained, ADR-0005) |
| Telemetry | Firebase Analytics + Crashlytics |
| Feature Flags / Tuning | Firebase Remote Config |
| Camera | `camera` plugin cho preview/capture; analysis ở native module |
| Architecture | Feature-first (`lib/features/<name>/`), core dùng chung ở `lib/core/` |
| Testing | flutter_test + mocktail; rule engine coverage ≥ 90% |

## Native Inference Module (trong app Flutter)

| Component | Choice |
|-----------|--------|
| Android | Kotlin + CameraX ImageAnalysis |
| iOS | Swift + AVCaptureVideoDataOutput |
| Pose | MediaPipe Pose Landmarker (lite model, GPU delegate) |
| Face / Object / Labeling | Google ML Kit |
| Custom models | TensorFlow Lite runtime |
| Bridge | EventChannel `shotmate/frame_analysis` — CHỈ gửi kết quả JSON ≤ 2KB |

## Backend Golden Path (NestJS — từ Sprint 3)

| Component | Choice |
|-----------|--------|
| Framework | NestJS + Fastify adapter |
| Language | TypeScript strict mode |
| Database | PostgreSQL |
| ORM | Prisma |
| Queue | BullMQ (Redis) |
| Cache | Redis (Memorystore) |
| Auth | Magic link email + JWT (access 15m / refresh 30d rotation) |
| Realtime | WebSocket (khi cần push kết quả review) |
| Validation | class-validator + zod cho AI output schema |
| Testing | Vitest + Supertest |
| Logging | pino structured JSON |
| Observability | OpenTelemetry (OTLP) → Cloud Monitoring/Trace |

## AI

| Component | Choice |
|-----------|--------|
| Realtime guidance | Rule engine deterministic pure Dart — KHÔNG LLM realtime (ADR-0003) |
| Cloud review | `AiReviewProvider` adapter: Claude (Haiku/Sonnet vision) + Gemini Flash (ADR-0004) |
| Provider switch | Config/Remote Config, failover tự động |
| Ảnh gửi cloud | Resize ≤ 1568px cạnh dài, opt-in |

## Infrastructure

| Component | Choice |
|-----------|--------|
| Compute | GCP Cloud Run (api + worker riêng service) |
| Database | Cloud SQL PostgreSQL |
| Cache/Queue | Memorystore Redis |
| Storage | Cloud Storage + Cloud CDN |
| WAF | Cloud Armor |
| Secrets | GCP Secret Manager |
| CI/CD | GitHub Actions |
| Mobile release | Fastlane → TestFlight / Play Internal |
| Local dev | Docker Compose: postgres, redis, minio, mailpit, backend |

## Configuration Management

| Component | Choice |
|-----------|--------|
| Backend config | `.env` local (gitignored), Secret Manager trên GCP |
| Required backend vars | `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GCS_BUCKET`, `SMTP_*` |
| App config | Firebase Remote Config + compile-time flavors (dev/staging/prod) |

## Prohibited Patterns

- ❌ KHÔNG stream raw camera frame qua platform channel (ADR-0001)
- ❌ KHÔNG gọi LLM trong realtime guidance loop (ADR-0003)
- ❌ KHÔNG dùng Isar (unmaintained — ADR-0005)
- ❌ KHÔNG upload ảnh/frame khi user chưa opt-in (NFR-3, privacy)
- ❌ KHÔNG hardcode secrets (dùng env/Secret Manager)
- ❌ KHÔNG logic nghiệp vụ trong native module — native chỉ detect, mọi quyết định ở Rule Engine Dart
- ❌ KHÔNG tin client về subscription — IAP receipt verify server-side
- ❌ KHÔNG `prisma db push` lên môi trường chung — dùng Prisma Migrate
