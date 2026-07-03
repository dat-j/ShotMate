# ADR-0002: Offline-first MVP — backend hoãn đến Sprint 3

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** architecture, backend, mvp
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ✅ Follows Golden Path

---

## Context

Toàn bộ 7 feature MVP (Live Composition, Zoom, Pose, Distance, Angle, Countdown, Photo Score) chạy được 100% on-device: detection native (ADR-0001), guidance + scoring bằng rule engine (ADR-0003), history bằng Drift (ADR-0005). Backend chỉ thực sự cần cho: đăng nhập, sync đa thiết bị, subscription verify, cloud AI review.

Solo dev, 6 tuần đến beta. Câu hỏi: dựng backend từ Sprint 1 hay hoãn?

---

## Decision Drivers

- Time-to-beta ngắn nhất có thể (feedback loop với user thật là ưu tiên 1)
- Realtime guidance không được phụ thuộc mạng (NFR-4)
- Free tier 10 phân tích/ngày cần enforce — nhưng mức độ chặt chẽ nào là đủ cho beta?
- Chi phí vận hành giai đoạn chưa có doanh thu ≈ 0

---

## Considered Options

### Option 1: Backend từ Sprint 1

Dựng NestJS + Cloud Run + Postgres ngay, app gọi API từ ngày đầu (analytics, credit, config).

| Pros | Cons |
|------|------|
| Credit enforce server-side từ đầu, không bypass được | +1–2 tuần setup trước khi có feature user thấy được |
| Data model server ổn định sớm | App phụ thuộc mạng không cần thiết; thêm failure mode |
| | Chi phí GCP chạy từ ngày 0 |

### Option 2: Offline-first — backend vào Sprint 3

Sprint 1–2 app standalone: không login, history local, credit đếm device-local. Sprint 3 thêm backend cho auth/sync/subscription/cloud review, cùng lúc với beta.

| Pros | Cons |
|------|------|
| Beta được ngay sau Sprint 2 (TestFlight/Internal track không cần server) | Credit device-local bypass được (xoá app data) |
| 100% effort Sprint 1–2 vào camera pipeline — phần rủi ro nhất | Sync history về sau phải migrate local data (cần thiết kế ID trước) |
| App core không bao giờ chết vì server chết | |
| Chi phí = 0 đến Sprint 3 | |

---

## Decision Outcome

**Chosen Option:** Option 2 — Offline-first, backend Sprint 3

**Rationale:** Rủi ro lớn nhất của sản phẩm là camera pipeline không đạt latency/UX — không phải backend (NestJS CRUD là việc đã biết cách làm). Dồn Sprint 1–2 vào rủi ro chính. Credit bypass ở beta chấp nhận được: free tier lúc này là công cụ đo hành vi, chưa phải hàng rào doanh thu. Điều kiện bắt buộc để sync sau không đau: **Photo/Analysis dùng UUID sinh tại client ngay từ Sprint 1** — server chỉ nhận, không cấp lại ID.

### Quantified Impact

| Metric | Backend từ đầu | Offline-first | Notes |
|--------|----------------|---------------|-------|
| Time-to-beta | ~8 tuần | ~4–5 tuần | Beta sau Sprint 2 |
| Chi phí GCP tháng 1–2 | ~$30–50/tháng | $0 | Cloud SQL + Redis nhỏ |
| Failure modes ở MVP | app + network + server | app only | |

---

## Consequences

**Positive:**
- Beta sớm 3+ tuần; feedback vào trước khi backend đông cứng data model
- App được thiết kế degrade gracefully từ gốc — server chết thì mất review/sync, guidance vẫn chạy

**Negative:**
- Free-tier bypass được đến Sprint 3
- Sprint 3 dày: auth + sync + subscription + review pipeline trong 2 tuần (đã phản ánh trong roadmap risk)

**Risks:**
- Local schema không tương thích server schema → mitigate: Drift schema mirror ERD trong System Design ngay từ đầu, UUID client-side, cột `synced_at` nullable

---

## Validation

- [ ] Sprint 2 kết thúc: app dùng được end-to-end không có mạng (airplane mode test)
- [ ] Local schema có UUID + synced_at sẵn cho sync
- [x] Tech Strategy alignment confirmed

---

## Links

- [PRD](../prd/PRD-shotmate-mvp.md) · [System Design](../design/system-design-shotmate.md) · [Roadmap](../roadmap.md) · [ADR-0005 Drift](./0005-local-storage-drift.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
