import { signedJwt } from './jwt';
import {
  appleTransaction,
  appStoreBundleId,
  signedTransactionsFromStatus,
  verifyAppleSignedPayload,
  type AppleTransaction,
} from './apple_jws';
import {
  subscriptionProducts,
  type VerifiedPurchase,
} from './entitlements';
import { playOneTime, playPackageName, playSubscription, type PlayPurchase } from './play_purchase';

export class StoreUnavailable extends Error {}

export type StoreFetch = { status: 'verified'; purchase: VerifiedPurchase } | { status: 'unknown' };

export type AppStoreCredentials = { issuerId: string; keyId: string; privateKey: string };
export type PlayCredentials = { email: string; privateKey: string };

type FetchImpl = typeof fetch;

export function verifiedApple(transaction: AppleTransaction): VerifiedPurchase {
  return {
    store: 'app_store',
    productId: transaction.productId,
    token: transaction.originalTransactionId,
    expiresAt: transaction.expiresAt,
    revoked: transaction.revoked,
    signedDate: transaction.signedDate,
    accountToken: transaction.appAccountToken,
    environment: transaction.environment,
    subscription: subscriptionProducts.has(transaction.productId),
  };
}

export function verifiedPlay(purchase: PlayPurchase, token: string): VerifiedPurchase {
  return {
    store: 'play',
    productId: purchase.productId,
    token,
    expiresAt: purchase.expiresAt,
    revoked: purchase.revoked,
    accountToken: purchase.obfuscatedAccountId,
    environment: null,
    subscription: purchase.subscription,
  };
}

export function appStoreToken(credentials: AppStoreCredentials, nowMs: number): string {
  const now = Math.floor(nowMs / 1000);
  return signedJwt(
    { alg: 'ES256', kid: credentials.keyId, typ: 'JWT' },
    {
      iss: credentials.issuerId,
      iat: now,
      exp: now + 300,
      aud: 'appstoreconnect-v1',
      bid: appStoreBundleId,
    },
    credentials.privateKey,
    'ES256',
  );
}

export function playServiceToken(credentials: PlayCredentials, nowMs: number): string {
  const now = Math.floor(nowMs / 1000);
  return signedJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: credentials.email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    credentials.privateKey,
    'RS256',
  );
}

function hosts(environment: string | null): string[] {
  const production = 'https://api.storekit.itunes.apple.com';
  const sandbox = 'https://api.storekit-sandbox.itunes.apple.com';
  return environment === 'Sandbox' ? [sandbox, production] : [production, sandbox];
}

const storeFetchTimeoutMs = 15_000;

async function readJson(response: Response, label: string): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    throw new StoreUnavailable(`${label} json`);
  }
}

/// Current subscription state from the App Store Server API.
export async function fetchAppleSubscription(
  originalTransactionId: string,
  environment: string | null,
  credentials: AppStoreCredentials,
  now: number,
  fetchImpl: FetchImpl,
): Promise<StoreFetch> {
  if (!/^[0-9]{1,32}$/.test(originalTransactionId)) return { status: 'unknown' };
  const bearer = appStoreToken(credentials, now);
  let sawUnknown = false;
  for (const host of hosts(environment)) {
    let response: Response;
    try {
      response = await fetchImpl(
        `${host}/inApps/v1/subscriptions/${originalTransactionId}`,
        {
          headers: { Authorization: `Bearer ${bearer}` },
          signal: AbortSignal.timeout(storeFetchTimeoutMs),
        },
      );
    } catch {
      throw new StoreUnavailable('app store unreachable');
    }
    if (response.status === 404) {
      sawUnknown = true;
      continue;
    }
    if (!response.ok) throw new StoreUnavailable(`app store ${response.status}`);
    const signed = signedTransactionsFromStatus(await readJson(response, 'app store'));
    let best: VerifiedPurchase | null = null;
    for (const jws of signed) {
      const payload = verifyAppleSignedPayload(jws, now);
      if (!payload) continue;
      const transaction = appleTransaction(payload);
      if (!transaction || transaction.originalTransactionId !== originalTransactionId) continue;
      const purchase = verifiedApple(transaction);
      if (!best || (purchase.expiresAt ?? 0) >= (best.expiresAt ?? 0)) best = purchase;
    }
    if (!best) throw new StoreUnavailable('app store signature');
    return { status: 'verified', purchase: best };
  }
  if (sawUnknown) return { status: 'unknown' };
  throw new StoreUnavailable('app store');
}

/// Current single-transaction state (including revocations) from the App Store Server API.
export async function fetchAppleTransaction(
  transactionId: string,
  environment: string | null,
  credentials: AppStoreCredentials,
  now: number,
  fetchImpl: FetchImpl,
): Promise<StoreFetch> {
  if (!/^[0-9]{1,32}$/.test(transactionId)) return { status: 'unknown' };
  const bearer = appStoreToken(credentials, now);
  let sawUnknown = false;
  for (const host of hosts(environment)) {
    let response: Response;
    try {
      response = await fetchImpl(
        `${host}/inApps/v1/transactions/${transactionId}`,
        {
          headers: { Authorization: `Bearer ${bearer}` },
          signal: AbortSignal.timeout(storeFetchTimeoutMs),
        },
      );
    } catch {
      throw new StoreUnavailable('app store unreachable');
    }
    if (response.status === 404) {
      sawUnknown = true;
      continue;
    }
    if (!response.ok) throw new StoreUnavailable(`app store ${response.status}`);
    const body = (await readJson(response, 'app store')) as { signedTransactionInfo?: unknown };
    const signed = body?.signedTransactionInfo;
    if (typeof signed !== 'string' || signed.length === 0) {
      throw new StoreUnavailable('app store body');
    }
    const payload = verifyAppleSignedPayload(signed, now);
    const transaction = payload ? appleTransaction(payload) : null;
    if (!transaction) throw new StoreUnavailable('app store signature');
    return { status: 'verified', purchase: verifiedApple(transaction) };
  }
  if (sawUnknown) return { status: 'unknown' };
  throw new StoreUnavailable('app store');
}

async function playAccessToken(credentials: PlayCredentials, fetchImpl: FetchImpl, now: number): Promise<string> {
  const assertion = playServiceToken(credentials, now);
  let response: Response;
  try {
    response = await fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${encodeURIComponent(assertion)}`,
      signal: AbortSignal.timeout(storeFetchTimeoutMs),
    });
  } catch {
    throw new StoreUnavailable('play auth unreachable');
  }
  if (!response.ok) throw new StoreUnavailable(`play auth ${response.status}`);
  const body = (await readJson(response, 'play auth')) as { access_token?: unknown };
  if (typeof body.access_token !== 'string' || body.access_token.length === 0) {
    throw new StoreUnavailable('play auth token');
  }
  return body.access_token;
}

async function playGet(url: string, accessToken: string, fetchImpl: FetchImpl): Promise<{ status: number; body: unknown }> {
  let response: Response;
  try {
    response = await fetchImpl(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
      signal: AbortSignal.timeout(storeFetchTimeoutMs),
    });
  } catch {
    throw new StoreUnavailable('play unreachable');
  }
  if (response.status === 404) return { status: 404, body: null };
  if (!response.ok) throw new StoreUnavailable(`play ${response.status}`);
  return { status: response.status, body: await readJson(response, 'play') };
}

/// Live Play purchase. Subscriptions use subscriptionsv2. One-time products
/// use the product id the proof was stored under.
export async function fetchPlayPurchase(
  token: string,
  productId: string,
  subscription: boolean,
  credentials: PlayCredentials,
  now: number,
  fetchImpl: FetchImpl,
  accessToken?: string,
): Promise<StoreFetch> {
  if (token.length < 8 || token.length > 4096) return { status: 'unknown' };
  const bearer = accessToken ?? (await playAccessToken(credentials, fetchImpl, now));
  const encoded = encodeURIComponent(token);
  const root = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${playPackageName}`;
  const url = subscription
    ? `${root}/purchases/subscriptionsv2/tokens/${encoded}`
    : `${root}/purchases/products/${encodeURIComponent(productId)}/tokens/${encoded}`;
  const result = await playGet(url, bearer, fetchImpl);
  if (result.status === 404) return { status: 'unknown' };
  const parsed = subscription ? playSubscription(result.body, now) : playOneTime(result.body, productId);
  if (!parsed) throw new StoreUnavailable('play body');
  return { status: 'verified', purchase: verifiedPlay(parsed, token) };
}

export async function playBearer(credentials: PlayCredentials, fetchImpl: FetchImpl, now: number): Promise<string> {
  return playAccessToken(credentials, fetchImpl, now);
}

export function playCredentialsOf(raw: string): PlayCredentials | null {
  try {
    const parsed = JSON.parse(raw) as { client_email?: unknown; private_key?: unknown };
    if (typeof parsed.client_email !== 'string' || typeof parsed.private_key !== 'string') return null;
    if (parsed.client_email.length === 0 || parsed.private_key.length === 0) return null;
    return { email: parsed.client_email, privateKey: parsed.private_key };
  } catch {
    return null;
  }
}
