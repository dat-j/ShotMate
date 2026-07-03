# 📸 ShotMate — AI Camera Coach

> AI sẽ hướng dẫn bạn chụp được bức ảnh đẹp **ngay từ lần đầu** — trước khi bấm nút, không phải sau khi chụp.

```
"Lùi thêm 30 cm."   "Chuyển sang 2x."   "Nghiêng điện thoại 5°."   "Giơ cằm lên một chút."
```

Realtime <100ms, chạy hoàn toàn on-device. Cloud AI (Claude / Gemini Flash) chỉ dùng để chấm điểm và giải thích **sau** khi chụp.

## Trạng thái

🚧 **Bootstrap** — docs + scaffold hoàn chỉnh, Sprint 1 chưa bắt đầu. Xem [docs/roadmap.md](docs/roadmap.md).

## Tài liệu

| Tài liệu | Nội dung |
|----------|----------|
| [PRD](docs/prd/PRD-shotmate-mvp.md) | Vision, personas, 7 features MVP, monetization, metrics |
| [System Design](docs/design/system-design-shotmate.md) | Kiến trúc C4, realtime pipeline, data model, infra GCP |
| [ADR 0001–0006](docs/adr/) | Native frame processing, offline-first, rule engine, AI adapter, Drift, ML stack |
| [Spec Sprint 1](docs/specs/spec-sprint-1.md) | Yêu cầu chi tiết + acceptance criteria sprint đầu |
| [Roadmap](docs/roadmap.md) | 3 sprint MVP + V1→V4 |

## Cấu trúc

```
shotmate/
├── app/        Flutter app (iOS + Android) — camera, overlay, rule engine, history
├── backend/    NestJS API + review worker (kích hoạt ở Sprint 3)
├── infra/      docker-compose local + GitHub Actions workflows
└── docs/       PRD / System Design / ADRs / Specs / Roadmap
```

## Chạy local

### App (cần [Flutter SDK](https://docs.flutter.dev/get-started/install) — chưa cài trên máy này)

```bash
cd app
flutter pub get
dart run build_runner build -d    # codegen freezed/drift
flutter test
flutter run                        # cần thiết bị thật để test camera
```

> ⚠️ Scaffold này được tạo thủ công (máy chưa có Flutter SDK). Sau khi cài Flutter, chạy
> `flutter create --org dev.tranxuandat --project-name shotmate_app .` trong `app/` để sinh
> android/ios runner đầy đủ, rồi giữ lại `lib/`, `test/`, `pubspec.yaml` của repo.

### Backend (Sprint 3 — skeleton sẵn sàng)

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis
cd backend
cp .env.example .env
npm install
npm run build && npm test
npm run start:dev
```

## Nguyên tắc kiến trúc (tóm tắt)

1. **Pixel không rời native side** — analysis chạy Kotlin/Swift, chỉ kết quả (~1KB) về Dart
2. **Rule engine deterministic** quyết định mọi hint — không LLM trong realtime loop
3. **Offline-first** — guidance + score chạy 100% không mạng
4. **Privacy** — ảnh chỉ upload khi user opt-in cloud review

Chi tiết: [docs/adr/](docs/adr/) · Tech choices: [.claude/rules/tech-strategy.md](.claude/rules/tech-strategy.md)
