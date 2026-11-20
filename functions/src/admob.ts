import { verify } from 'node:crypto';

const keysUrl = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
const keysTtlMs = 24 * 60 * 60 * 1000;
const refreshCooldownMs = 5 * 60 * 1000;

let cachedKeys: Map<string, string> | undefined;
let cachedAt = 0;

async function verifierKeys(refresh: boolean): Promise<Map<string, string>> {
  const age = Date.now() - cachedAt;
  if (cachedKeys && ((!refresh && age < keysTtlMs) || (refresh && age < refreshCooldownMs))) {
    return cachedKeys;
  }
  const response = await fetch(keysUrl, { signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`AdMob verifier keys ${response.status}`);
  const body = (await response.json()) as { keys?: { keyId: number; pem: string }[] };
  cachedKeys = new Map((body.keys ?? []).map((key) => [String(key.keyId), key.pem]));
  cachedAt = Date.now();
  return cachedKeys;
}

/**
 * Checks an AdMob rewarded-ad server-side verification callback. The signed
 * message is the raw query string up to `&signature=`, in the order AdMob sent
 * it, so it must not be rebuilt from parsed parameters. Returned parameters
 * come strictly from the signed prefix so suffix parameters cannot be smuggled.
 */
export async function verifyAdmobCallback(rawQuery: string): Promise<URLSearchParams | null> {
  const cut = rawQuery.indexOf('&signature=');
  if (cut < 0) return null;
  const signedPrefix = rawQuery.slice(0, cut);
  const tailParams = new URLSearchParams(rawQuery.slice(cut + 1));
  const signature = tailParams.get('signature');
  const keyId = tailParams.get('key_id');
  if (!signature || !keyId) return null;
  const message = Buffer.from(signedPrefix, 'utf8');
  const signatureBytes = Buffer.from(signature, 'base64url');
  let keys = await verifierKeys(false);
  if (!keys.has(keyId)) keys = await verifierKeys(true);
  const pem = keys.get(keyId);
  if (!pem) return null;
  const ok = verify('sha256', message, { key: pem, dsaEncoding: 'der' }, signatureBytes);
  return ok ? new URLSearchParams(signedPrefix) : null;
}
