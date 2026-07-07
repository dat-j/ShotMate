import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../../common/http/http-error.filter';
import { SubscriptionsController } from './subscriptions.controller';
import { SubscriptionsService } from './subscriptions.service';

const SECRET = 'whsec_test_secret';

function controller(overrides?: { upsertFromEntitlement?: unknown }) {
  const subscriptions = {
    upsertFromEntitlement: vi.fn(async () => overrides?.upsertFromEntitlement ?? undefined),
    currentPlan: vi.fn(),
  } as unknown as SubscriptionsService;

  const config = {
    get: vi.fn(() => SECRET),
  };

  return {
    ctrl: new SubscriptionsController(subscriptions, config as never),
    subscriptions,
    config,
  };
}

describe('SubscriptionsController.handleWebhook (spec FR-S4-5/D4, CWE-20)', () => {
  it('payload hợp lệ → xử lý bình thường (upsert premium)', async () => {
    const { ctrl, subscriptions } = controller();

    const result = await ctrl.handleWebhook(SECRET, {
      event: {
        type: 'INITIAL_PURCHASE',
        app_user_id: 'user-1',
        expiration_at_ms: 1_800_000_000_000,
        store: 'google',
      },
    });

    expect(result).toEqual({});
    expect(subscriptions.upsertFromEntitlement).toHaveBeenCalledWith({
      userId: 'user-1',
      plan: 'premium',
      store: 'google',
      expiresAt: new Date(1_800_000_000_000),
      receiptRef: 'user-1',
    });
  });

  it('thiếu type → 422 VALIDATION_FAILED, không upsert', async () => {
    const { ctrl, subscriptions } = controller();

    await expect(
      ctrl.handleWebhook(SECRET, {
        event: { app_user_id: 'user-2' } as never,
      }),
    ).rejects.toMatchObject({
      status: 422,
      code: 'VALIDATION_FAILED',
    } as Partial<AppError>);

    expect(subscriptions.upsertFromEntitlement).not.toHaveBeenCalled();
  });

  it('thiếu app_user_id → 422 VALIDATION_FAILED, không upsert', async () => {
    const { ctrl, subscriptions } = controller();

    await expect(
      ctrl.handleWebhook(SECRET, {
        event: { type: 'RENEWAL' } as never,
      }),
    ).rejects.toMatchObject({
      status: 422,
      code: 'VALIDATION_FAILED',
    } as Partial<AppError>);

    expect(subscriptions.upsertFromEntitlement).not.toHaveBeenCalled();
  });

  it('app_user_id rỗng → 422 VALIDATION_FAILED', async () => {
    const { ctrl } = controller();

    await expect(
      ctrl.handleWebhook(SECRET, {
        event: { type: 'RENEWAL', app_user_id: '' },
      }),
    ).rejects.toMatchObject({ status: 422, code: 'VALIDATION_FAILED' } as Partial<AppError>);
  });

  it('field lạ không nhận diện được → bỏ qua an toàn, field đã biết xử lý bình thường', async () => {
    const { ctrl, subscriptions } = controller();

    const result = await ctrl.handleWebhook(SECRET, {
      event: {
        type: 'CANCELLATION',
        app_user_id: 'user-3',
        environment: 'SANDBOX',
        some_new_field: { nested: true },
      } as never,
      extra_top_level_field: 'ignored',
    } as never);

    expect(result).toEqual({});
    expect(subscriptions.upsertFromEntitlement).toHaveBeenCalledWith({
      userId: 'user-3',
      plan: 'free',
      store: null,
      expiresAt: null,
      receiptRef: 'user-3',
    });
  });

  it('event type không active/inactive (không quan tâm) → không upsert, trả {}', async () => {
    const { ctrl, subscriptions } = controller();

    const result = await ctrl.handleWebhook(SECRET, {
      event: { type: 'BILLING_ISSUE', app_user_id: 'user-4' },
    });

    expect(result).toEqual({});
    expect(subscriptions.upsertFromEntitlement).not.toHaveBeenCalled();
  });

  it('secret sai → 401 dù payload hợp lệ', async () => {
    const { ctrl, subscriptions } = controller();

    await expect(
      ctrl.handleWebhook('wrong-secret', {
        event: { type: 'INITIAL_PURCHASE', app_user_id: 'user-5' },
      }),
    ).rejects.toMatchObject({ status: 401, code: 'WEBHOOK_UNAUTHORIZED' } as Partial<AppError>);

    expect(subscriptions.upsertFromEntitlement).not.toHaveBeenCalled();
  });

  it('secret sai → vẫn 401 dù payload không hợp lệ (401 ưu tiên hơn 422)', async () => {
    const { ctrl, subscriptions } = controller();

    await expect(
      ctrl.handleWebhook('wrong-secret', {
        event: { app_user_id: '' } as never,
      }),
    ).rejects.toMatchObject({ status: 401, code: 'WEBHOOK_UNAUTHORIZED' } as Partial<AppError>);

    expect(subscriptions.upsertFromEntitlement).not.toHaveBeenCalled();
  });

  it('thiếu authorization header → 401', async () => {
    const { ctrl } = controller();

    await expect(
      ctrl.handleWebhook(undefined, {
        event: { type: 'INITIAL_PURCHASE', app_user_id: 'user-6' },
      }),
    ).rejects.toMatchObject({ status: 401, code: 'WEBHOOK_UNAUTHORIZED' } as Partial<AppError>);
  });
});
