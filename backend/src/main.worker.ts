import { createServer } from 'node:http';

import { NestFactory } from '@nestjs/core';

import { WorkerModule } from './worker.module';

/**
 * Entry point riêng cho worker BullMQ (spec-sprint-4 FR-S4-2, D2). DI
 * container + `Worker`/`Queue` BullMQ tự giữ event loop busy qua kết nối
 * Redis — không cần `app.listen`. Cloud Run Service (khác Jobs) vẫn bắt
 * buộc container lắng nghe `$PORT` để pass startup/liveness probe dù
 * `--no-allow-unauthenticated` chặn hết traffic ngoài, nên mở kèm 1 HTTP
 * server tối giản chỉ trả 200 cho probe — không phục vụ business logic.
 */
async function bootstrap(): Promise<void> {
  await NestFactory.createApplicationContext(WorkerModule);

  const port = Number(process.env.PORT) || 8080;
  createServer((_req, res) => {
    res.writeHead(200).end('ok');
  }).listen(port);
}

void bootstrap();
