export const playPackageName = 'sk.ab.herbs';

const activeSubscriptionStates = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);

export type PlayPurchase = {
  productId: string;
  expiresAt: number | null;
  revoked: boolean;
  obfuscatedAccountId: string | null;
  subscription: boolean;
};

function obfuscatedAccount(record: Record<string, unknown>): string | null {
  const nested = record.externalAccountIdentifiers;
  if (nested && typeof nested === 'object') {
    const id = (nested as { obfuscatedExternalAccountId?: unknown }).obfuscatedExternalAccountId;
    if (typeof id === 'string' && id.length > 0) return id;
  }
  const direct = record.obfuscatedExternalAccountId;
  return typeof direct === 'string' && direct.length > 0 ? direct : null;
}

/// Subscriptions v2. A canceled plan stays active until its expiry.
/// A license test follows the same states. `testPurchase` only means the
/// tester was not charged.
export function playSubscription(body: unknown, now: number): PlayPurchase | null {
  if (!body || typeof body !== 'object') return null;
  const record = body as Record<string, unknown>;
  const state = record.subscriptionState;
  if (typeof state !== 'string' || !Array.isArray(record.lineItems)) return null;
  let best: { productId: string; expiresAt: number } | null = null;
  for (const item of record.lineItems) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    if (typeof row.productId !== 'string' || typeof row.expiryTime !== 'string') continue;
    if (!/^[A-Za-z0-9_]{1,64}$/.test(row.productId)) continue;
    const expiresAt = Date.parse(row.expiryTime);
    if (!Number.isFinite(expiresAt)) continue;
    if (!best || expiresAt > best.expiresAt) best = { productId: row.productId, expiresAt };
  }
  if (!best) return null;
  const stateActive = activeSubscriptionStates.has(state);
  return {
    productId: best.productId,
    expiresAt: best.expiresAt,
    revoked: !stateActive || best.expiresAt <= now,
    obfuscatedAccountId: obfuscatedAccount(record),
    subscription: true,
  };
}

/// One-time product. purchaseState 0 is purchased, 1 is canceled.
/// A license test (`purchaseType` 0 or `testPurchase`) grants when purchased.
export function playOneTime(body: unknown, productId: string): PlayPurchase | null {
  if (!body || typeof body !== 'object') return null;
  if (!/^[A-Za-z0-9_]{1,64}$/.test(productId)) return null;
  const record = body as Record<string, unknown>;
  const state = record.purchaseState;
  if (state !== 0 && state !== 1) return null;
  return {
    productId,
    expiresAt: null,
    revoked: state === 1,
    obfuscatedAccountId: obfuscatedAccount(record),
    subscription: false,
  };
}
