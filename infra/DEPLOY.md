# Deploy Cloud Run — hướng dẫn thủ công (Sprint 4, FR-S4-1)

<!--
Ghi chú phạm vi: môi trường thực thi Sprint 4 KHÔNG có `gcloud`/GCP project/
credentials. File này là hướng dẫn CHUẨN BỊ SẴN — Dockerfile + lệnh mẫu — để
chủ dự án (Đạt) tự chạy khi có GCP project + billing thật. Không có bước nào
trong tài liệu này đã được thực thi tự động.
-->

## Trước khi bắt đầu

- GCP project đã tạo, billing đã bật.
- `gcloud` CLI cài đặt + `gcloud auth login` + `gcloud config set project <PROJECT_ID>`.
- API cần bật: `run.googleapis.com`, `sqladmin.googleapis.com`, `redis.googleapis.com`, `secretmanager.googleapis.com`, `artifactregistry.googleapis.com`.

## 1. Hạ tầng dữ liệu

```bash
# Cloud SQL PostgreSQL (tier nhỏ nhất đủ cho beta)
gcloud sql instances create shotmate-db \
  --database-version=POSTGRES_17 \
  --tier=db-f1-micro \
  --region=asia-southeast1

gcloud sql databases create shotmate --instance=shotmate-db
gcloud sql users set-password postgres --instance=shotmate-db --password=<CHOOSE_STRONG_PASSWORD>

# Memorystore Redis (1GB, basic tier đủ cho beta — không cần HA)
gcloud redis instances create shotmate-redis \
  --size=1 \
  --region=asia-southeast1 \
  --tier=basic

# GCS bucket cho ảnh (private — uniform bucket-level access)
gcloud storage buckets create gs://shotmate-photos-prod \
  --location=asia-southeast1 \
  --uniform-bucket-level-access
```

## 2. Secret Manager

Tạo secret cho từng biến sau (xem `backend/.env.example` cho mô tả đầy đủ từng biến):

```bash
for name in DATABASE_URL REDIS_URL JWT_SECRET ANTHROPIC_API_KEY GEMINI_API_KEY \
  SMTP_HOST SMTP_PORT SMTP_FROM REVENUECAT_WEBHOOK_SECRET REVENUECAT_API_KEY \
  STORAGE_ACCESS_KEY STORAGE_SECRET_KEY; do
  gcloud secrets create "$name" --replication-policy=automatic
done
# Sau đó set giá trị thật cho từng secret:
#   echo -n "<value>" | gcloud secrets versions add DATABASE_URL --data-file=-
```

Lưu ý riêng:
- `JWT_SECRET` ≥ 16 ký tự random — KHÔNG dùng lại cho `STORAGE_ACCESS_KEY`/`STORAGE_SECRET_KEY` (finding L2, xem `storage.service.ts`).
- `DATABASE_URL` trỏ Cloud SQL qua Cloud SQL Auth Proxy hoặc Private IP — không expose public IP.
- `GCS_BUCKET` không cần secret (không nhạy cảm) — set thẳng qua `--set-env-vars`.

## 3. Build + push image (2 target: api, worker)

```bash
gcloud artifacts repositories create shotmate --repository-format=docker \
  --location=asia-southeast1

REGION=asia-southeast1
REPO=$REGION-docker.pkg.dev/<PROJECT_ID>/shotmate

docker build --target api    -t $REPO/api:latest    backend/
docker build --target worker -t $REPO/worker:latest backend/

docker push $REPO/api:latest
docker push $REPO/worker:latest
```

## 4. Apply migration (lần đầu — EC-S4-6)

Chạy `prisma migrate deploy` **trước** khi deploy revision mới, từ máy có network tới Cloud SQL (qua Cloud SQL Auth Proxy) hoặc như một Cloud Run Job riêng:

```bash
cloud-sql-proxy <PROJECT_ID>:asia-southeast1:shotmate-db &
DATABASE_URL="postgresql://postgres:<password>@localhost:5432/shotmate" \
  npx prisma migrate deploy
```

Fail → dừng, KHÔNG deploy revision mới (EC-S4-6). Không sửa tay DB — sửa migration qua PR mới.

## 5. Deploy Cloud Run — 2 service riêng

```bash
# API — min-instances 0 (chấp nhận cold start <3s ở beta)
gcloud run deploy shotmate-api \
  --image=$REPO/api:latest \
  --region=$REGION \
  --min-instances=0 \
  --max-instances=10 \
  --add-cloudsql-instances=<PROJECT_ID>:asia-southeast1:shotmate-db \
  --vpc-connector=<CONNECTOR> \
  --set-secrets="DATABASE_URL=DATABASE_URL:latest,REDIS_URL=REDIS_URL:latest,JWT_SECRET=JWT_SECRET:latest,ANTHROPIC_API_KEY=ANTHROPIC_API_KEY:latest,GEMINI_API_KEY=GEMINI_API_KEY:latest,SMTP_HOST=SMTP_HOST:latest,REVENUECAT_WEBHOOK_SECRET=REVENUECAT_WEBHOOK_SECRET:latest,STORAGE_ACCESS_KEY=STORAGE_ACCESS_KEY:latest,STORAGE_SECRET_KEY=STORAGE_SECRET_KEY:latest" \
  --set-env-vars="GCS_BUCKET=shotmate-photos-prod"

# Worker — min-instances 1 (EC-S4-2: scale-to-zero sẽ bỏ đói BullMQ consumer)
gcloud run deploy shotmate-worker \
  --image=$REPO/worker:latest \
  --region=$REGION \
  --min-instances=1 \
  --max-instances=3 \
  --no-cpu-throttling \
  --add-cloudsql-instances=<PROJECT_ID>:asia-southeast1:shotmate-db \
  --vpc-connector=<CONNECTOR> \
  --set-secrets="DATABASE_URL=DATABASE_URL:latest,REDIS_URL=REDIS_URL:latest,ANTHROPIC_API_KEY=ANTHROPIC_API_KEY:latest,GEMINI_API_KEY=GEMINI_API_KEY:latest,STORAGE_ACCESS_KEY=STORAGE_ACCESS_KEY:latest,STORAGE_SECRET_KEY=STORAGE_SECRET_KEY:latest" \
  --set-env-vars="GCS_BUCKET=shotmate-photos-prod" \
  --no-allow-unauthenticated
```

`shotmate-worker` không cần nhận HTTP traffic — `--no-allow-unauthenticated` chặn truy cập ngoài; nó chỉ tiêu thụ job từ Redis.

## 6. GitHub Actions (CI/CD)

`infra/github-actions/ci.yml` đã có job build Docker cho cả 2 target. Job **deploy Cloud Run bị gate** (`workflow_dispatch` thủ công hoặc `if: false`) cho tới khi:

1. GCP project tồn tại + service account cho GitHub OIDC đã tạo (`gcloud iam workload-identity-pools create ...` — xem [tài liệu OIDC chính thức của GCP](https://cloud.google.com/iam/docs/workload-identity-federation-with-github-actions)).
2. Secret `WIF_PROVIDER` + `WIF_SERVICE_ACCOUNT` đã thêm vào GitHub repo secrets.

**Không dùng service account key file trong repo/CI log** — chỉ OIDC.

## 7. Alert (Cloud Monitoring) — FR-S4-6

Tạo thủ công qua Console hoặc `gcloud alpha monitoring policies create` sau khi có traffic thật:

| Alert | Điều kiện |
|-------|-----------|
| Error rate | > 5% request 5xx trong 5 phút |
| Queue depth | BullMQ `ai-review` waiting > 100 (cần custom metric qua OTel hoặc log-based metric) |
| Provider failure rate | > 20% review job fail chung cuộc trong 1 giờ |
| Worker im lặng | Không log nào từ `shotmate-worker` > 5 phút |

## 8. Ước tính chi phí (beta, ~50 users)

| Thành phần | Ước tính/tháng |
|-----------|----------------|
| Cloud Run api (min 0) | $0–5 |
| Cloud Run worker (min 1) | $10–15 |
| Cloud SQL db-f1-micro | $10–15 |
| Memorystore 1GB basic | $25–35 |
| GCS + egress | $1–5 |
| AI review (Claude/Gemini, ~$0.01/ảnh) | $5–10 |
| **Tổng** | **~$50–85/tháng** |

Xác nhận với chủ dự án trước khi tạo hạ tầng thật (Open Question spec-sprint-4).
