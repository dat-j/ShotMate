import { NestFactory } from '@nestjs/core';

import { WorkerModule } from './worker.module';

/**
 * Entry point riêng cho worker BullMQ (spec-sprint-4 FR-S4-2, D2). Không HTTP
 * listener — `createApplicationContext` khởi tạo DI container rồi giữ
 * process sống qua các `Worker`/`Queue` BullMQ (chúng tự giữ event loop busy
 * qua kết nối Redis, không cần `app.listen`).
 */
async function bootstrap(): Promise<void> {
  await NestFactory.createApplicationContext(WorkerModule);
}

void bootstrap();
