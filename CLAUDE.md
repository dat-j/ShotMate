# ShotMate — AI Camera Coach

App camera Flutter (iOS + Android) hướng dẫn người dùng chụp ảnh đẹp **trước khi bấm nút** — composition, pose, zoom, distance, angle — realtime <100ms, chạy on-device. Cloud AI (Claude/Gemini) chỉ review ảnh sau khi chụp.

## Core Principles

1. **Realtime là số 1**: mọi thay đổi vào camera pipeline phải giữ frame→hint <100ms p90. Pixel không bao giờ rời native side (xem ADR-0001).
2. **Rule engine quyết định, native chỉ detect**: logic guidance nằm trong pure Dart (`app/lib/features/coach/domain/`), deterministic, coverage ≥ 90%. Không LLM realtime (ADR-0003).
3. **Offline-first**: app core không được phụ thuộc mạng. Backend chỉ cho auth/sync/subscription/cloud review (ADR-0002).
4. **Keep It Safe**: theo `.claude/rules/security.md`; ảnh user là dữ liệu nhạy cảm nhất — chỉ upload opt-in.

## Cấu trúc repo

```
app/       Flutter app (feature-first: lib/features/<name>/, dùng chung: lib/core/)
backend/   NestJS API + worker (Sprint 3+) — Prisma, BullMQ, AiReviewProvider adapter
docs/      PRD, System Design, ADRs, Specs, Roadmap — ĐỌC TRƯỚC KHI CODE
infra/     docker-compose local + GitHub Actions
```

## Tài liệu bắt buộc đọc theo task

- Feature mới / thay đổi hành vi → `docs/prd/PRD-shotmate-mvp.md` + spec tương ứng trong `docs/specs/`
- Quyết định kiến trúc → `docs/adr/` (0001–0006); deviation cần ADR mới
- Tech choice → `.claude/rules/tech-strategy.md` (single source of truth)

## Lệnh thường dùng

```bash
# App (cần Flutter SDK)
cd app && flutter pub get && dart run build_runner build -d   # codegen (freezed/drift)
cd app && flutter analyze && flutter test                      # quality gate

# Backend
cd backend && npm install && npm run build && npm test         # quality gate
docker compose -f infra/docker-compose.yml up -d postgres redis  # hạ tầng local

# Prisma (backend)
cd backend && npx prisma generate && npx prisma migrate dev
```

## Quality Gates (trước mọi commit)

- `flutter analyze` 0 issue + `flutter test` pass (nếu đổi app/)
- `npm run build` + `npm test` pass (nếu đổi backend/)
- Rule engine thay đổi → golden test fixtures cập nhật kèm
- Không secrets trong diff
