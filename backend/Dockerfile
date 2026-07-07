# Cloud Run image — 2 target riêng, api + worker (System Design §9,
# spec-sprint-4 FR-S4-1/FR-S4-2). Build:
#   docker build --target api    -t shotmate-api    backend/
#   docker build --target worker -t shotmate-worker backend/
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY prisma ./prisma
COPY src ./src
RUN npx prisma generate 2>/dev/null || true && npm run build

FROM node:22-alpine AS runtime-base
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
COPY prisma ./prisma

FROM runtime-base AS api
EXPOSE 8080
CMD ["node", "dist/main.js"]

FROM runtime-base AS worker
CMD ["node", "dist/main.worker.js"]
