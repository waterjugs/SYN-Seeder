// Checking that a request really comes from Discord. Discord signs every
// interaction with the app's private key; the Public Key on the Developer
// Portal checks the signature. A request that fails the check is refused.

const encoder = new TextEncoder();

// Discord's signatures are refused once they're this old (or this far ahead).
export const MAX_SIGNATURE_AGE_MS = 5 * 60 * 1000;

// Whether ``text`` looks like an app's Public Key: 64 hex characters.
export function isPublicKey(text) {
  return typeof text === 'string' && /^[0-9a-f]{64}$/i.test(text);
}

function hexBytes(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

// The imported key, kept between requests so it's imported once.
let cachedKey = { hex: '', key: null };

async function importKey(hex) {
  if (cachedKey.hex !== hex) {
    const key = await crypto.subtle.importKey('raw', hexBytes(hex), { name: 'Ed25519' }, false, ['verify']);
    cachedKey = { hex, key };
  }
  return cachedKey.key;
}

// Whether ``body`` was signed by the Discord app with ``publicKey``.
// ``signature`` and ``timestamp`` are the X-Signature-Ed25519 and
// X-Signature-Timestamp headers, ``now`` is Date.now().
export async function verifyRequest(publicKey, signature, timestamp, body, now) {
  if (!isPublicKey(publicKey)) return false;
  if (typeof signature !== 'string' || !/^[0-9a-f]{128}$/i.test(signature)) return false;
  if (typeof timestamp !== 'string' || !/^\d{1,12}$/.test(timestamp)) return false;
  if (Math.abs(now - Number(timestamp) * 1000) > MAX_SIGNATURE_AGE_MS) return false;
  try {
    const key = await importKey(publicKey.toLowerCase());
    return await crypto.subtle.verify({ name: 'Ed25519' }, key, hexBytes(signature), encoder.encode(timestamp + body));
  } catch {
    return false;
  }
}
