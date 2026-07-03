# ADR-0005: Local storage bằng Drift (SQLite) thay vì Hive/Isar

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** mobile, storage
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ⚠️ Deviation — brainstorm ban đầu đề xuất "Hive hoặc Isar"; xem Rationale

---

## Context

App offline-first (ADR-0002) cần local store cho: history ảnh + analysis + score (query theo ngày/scene/score, pagination), credit counter theo ngày, và sau Sprint 3 là trạng thái sync (`synced_at`). Đề xuất ban đầu trong brainstorm là "Hive hoặc Isar".

---

## Decision Drivers

- Query có điều kiện + sort + pagination cho history (không chỉ key-value)
- Schema migration an toàn khi app update (data user không được mất)
- Package phải được maintain chủ động (app sống nhiều năm)
- Type-safe, test được trên host (không cần device)
- Sẵn sàng cho sync: cần cột trạng thái + query "chưa sync"

---

## Considered Options

### Option 1: Isar

NoSQL embedded, từng là lựa chọn hot cho Flutter.

| Pros | Cons |
|------|------|
| Query nhanh, API đẹp | **Không còn maintain chủ động từ ~2023** (Isar 3 bỏ ngỏ, v4 không ra bản ổn định) |
| | Rủi ro chết dependency giữa vòng đời app — loại ngay từ driver 3 |

### Option 2: Hive / Hive CE

Key-value store thuần Dart.

| Pros | Cons |
|------|------|
| Nhẹ, nhanh, không native deps | Không query engine — filter history = load all rồi lọc trong memory |
| Tốt cho settings/cache đơn giản | Không migration schema có cấu trúc |

### Option 3: Drift

SQLite + type-safe query builder, codegen Dart.

| Pros | Cons |
|------|------|
| SQL đầy đủ: index, join, pagination cho history | Codegen (build_runner) — build step thêm |
| Migration versioned + test được | Verbose hơn Hive cho case đơn giản |
| Maintain rất chủ động, cộng đồng lớn | |
| Chạy test trên host qua NativeDatabase.memory() | |
| Schema mirror được ERD server (Postgres) → sync dễ | |

---

## Decision Outcome

**Chosen Option:** Option 3 — Drift

**Rationale:** Isar bị loại vì unmaintained (driver 3 là điều kiện cứng). Hive fail driver 1 và 2 — history là relational data có query thật. Drift thoả cả 5 driver; chi phí codegen chấp nhận được vì project đã dùng build_runner cho Freezed. Hive CE vẫn có thể dùng *bổ sung* cho settings key-value đơn giản nếu cần, nhưng không phải store chính.

### Quantified Impact

| Metric | Hive | Drift | Notes |
|--------|------|-------|-------|
| Query history 1000 ảnh filter scene + sort score | O(n) in-memory | O(log n) index | |
| Migration an toàn | Tự viết tay | Versioned API + test | |
| Maintenance risk | Thấp (CE fork) | Thấp | Isar: cao — loại |

---

## Consequences

**Positive:**
- History scale được (nghìn ảnh) không lo memory; sync Sprint 3 chỉ là thêm cột + query
- Test repository trên host, không cần emulator

**Negative:**
- Học Drift DSL + chờ build_runner (đã có sẵn trong workflow vì Freezed)

**Risks:**
- SQLite lock khi ghi từ isolate khác → dùng single database instance qua Riverpod provider, ghi qua 1 isolate

---

## Validation

- [ ] Repository test: insert 1000 photo + query filter/sort < 50ms trên host
- [ ] Migration test v1→v2 giữ nguyên data
- [x] Deviation documented (file này)

---

## Links

- [System Design §6 Data Model](../design/system-design-shotmate.md) · [ADR-0002 Offline-first](./0002-offline-first-backend-sprint-3.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
