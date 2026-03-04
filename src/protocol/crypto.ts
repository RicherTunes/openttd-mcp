/**
 * X25519 PAKE authentication and streaming encryption for OpenTTD 15+ admin port.
 *
 * Protocol flow:
 *   1. Client sends ADMIN_JOIN_SECURE (name, version, supported methods)
 *   2. Server sends SERVER_AUTH_REQUEST (method, server_pubkey, nonce)
 *   3. Client derives shared secret via X25519, then BLAKE2b key derivation with password
 *   4. Client encrypts 8 random bytes with XChaCha20-Poly1305, sends ADMIN_AUTH_RESPONSE
 *   5. Server sends SERVER_ENABLE_ENCRYPTION (encryption_nonce)
 *   6. Both sides switch to streaming encryption (ChaCha20-Poly1305 IETF with counter)
 */

import * as crypto from "node:crypto";
import sodium from "libsodium-wrappers";

// Constants matching OpenTTD's network_crypto_internal.h
export const X25519_KEY_SIZE = 32;
export const X25519_NONCE_SIZE = 24;
export const X25519_MAC_SIZE = 16;
export const X25519_KEY_EXCHANGE_MESSAGE_SIZE = 8;

/** Authentication methods bitmask */
export enum NetworkAuthMethod {
  X25519_KEY_EXCHANGE_ONLY = 0,
  X25519_PAKE = 1,
  X25519_AUTHORIZED_KEY = 2,
}

/** Ensure libsodium is initialized before use */
let sodiumReady = false;
export async function ensureSodiumReady(): Promise<void> {
  if (!sodiumReady) {
    await sodium.ready;
    sodiumReady = true;
  }
}

/**
 * Derive X25519 keypair from a random secret key.
 */
export function generateX25519Keypair(): { secretKey: Uint8Array; publicKey: Uint8Array } {
  const secretKey = sodium.randombytes_buf(X25519_KEY_SIZE);
  const publicKey = sodium.crypto_scalarmult_base(secretKey);
  return { secretKey, publicKey };
}

/**
 * Compute X25519 shared secret.
 */
export function x25519SharedSecret(
  ourSecretKey: Uint8Array,
  theirPublicKey: Uint8Array
): Uint8Array {
  const shared = sodium.crypto_scalarmult(ourSecretKey, theirPublicKey);
  // Check for all-zero shared secret (invalid peer key)
  if (shared.every((b) => b === 0)) {
    throw new Error("X25519 shared secret is all zeros — invalid peer public key");
  }
  return shared;
}

/**
 * Derive client-to-server and server-to-client keys using BLAKE2b.
 *
 * For the CLIENT side, the hash input order is:
 *   shared_secret || peer_public_key (server) || our_public_key (client) || password
 *
 * Output: 64 bytes = [ClientToServer (32)] [ServerToClient (32)]
 */
export function deriveKeys(
  sharedSecret: Uint8Array,
  serverPublicKey: Uint8Array,
  clientPublicKey: Uint8Array,
  password: string
): { clientToServer: Buffer; serverToClient: Buffer } {
  const hash = crypto.createHash("blake2b512");
  hash.update(sharedSecret);
  // CLIENT side: peer (server) first, then ours (client)
  hash.update(serverPublicKey);
  hash.update(clientPublicKey);
  hash.update(Buffer.from(password, "utf8"));
  const keys = hash.digest();
  // Return proper copies (not views) to avoid byteOffset issues with WASM bindings
  return {
    clientToServer: Buffer.from(keys.subarray(0, 32)),
    serverToClient: Buffer.from(keys.subarray(32, 64)),
  };
}

/**
 * One-shot XChaCha20-Poly1305 AEAD encrypt (for auth handshake).
 *
 * Matches Monocypher 4's crypto_aead_lock:
 *   crypto_aead_lock(cipher, mac, key, nonce24, ad, ad_size, plain, plain_size)
 *
 * Implemented as HChaCha20(key, nonce[0:16]) -> subkey,
 * then RFC 8439 ChaCha20-Poly1305 IETF with subkey and nonce = 0x00000000 || nonce[16:24].
 */
export function aeadEncrypt(
  key: Uint8Array | Buffer,
  nonce24: Uint8Array | Buffer,
  plaintext: Uint8Array | Buffer,
  ad: Uint8Array | Buffer
): { ciphertext: Buffer; mac: Buffer } {
  // Ensure we have proper Buffer copies (not views with byteOffset issues)
  const keyBuf = Buffer.from(key);
  const nonceBuf = Buffer.from(nonce24);
  const ptBuf = Buffer.from(plaintext);
  const adBuf = Buffer.from(ad);

  // Step 1: HChaCha20 to derive subkey from key + nonce[0:16]
  const subkey = hchacha20(keyBuf, nonceBuf.subarray(0, 16));

  // Step 2: Build 12-byte IETF nonce: 0x00000000 || nonce[16:24]
  const nonce12 = Buffer.alloc(12);
  nonceBuf.copy(nonce12, 4, 16, 24);

  // Step 3: RFC 8439 ChaCha20-Poly1305 IETF AEAD
  const cipher = crypto.createCipheriv("chacha20-poly1305", subkey, nonce12, {
    authTagLength: 16,
  });
  cipher.setAAD(adBuf, { plaintextLength: ptBuf.length });
  const ciphertext = Buffer.concat([cipher.update(ptBuf), cipher.final()]);
  const mac = cipher.getAuthTag();

  return { ciphertext, mac };
}

// ============ HChaCha20 for streaming AEAD ============

/** ChaCha20 quarter round */
function quarterRound(x: Uint32Array, a: number, b: number, c: number, d: number): void {
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl32(x[d] ^ x[a], 16);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl32(x[b] ^ x[c], 12);
  x[a] = (x[a] + x[b]) >>> 0; x[d] = rotl32(x[d] ^ x[a], 8);
  x[c] = (x[c] + x[d]) >>> 0; x[b] = rotl32(x[b] ^ x[c], 7);
}

function rotl32(v: number, n: number): number {
  return ((v << n) | (v >>> (32 - n))) >>> 0;
}

function readLE32(buf: Uint8Array | Buffer, offset: number): number {
  return (
    buf[offset] |
    (buf[offset + 1] << 8) |
    (buf[offset + 2] << 16) |
    (buf[offset + 3] << 24)
  ) >>> 0;
}

function writeLE32(buf: Buffer, offset: number, val: number): void {
  buf[offset] = val & 0xff;
  buf[offset + 1] = (val >>> 8) & 0xff;
  buf[offset + 2] = (val >>> 16) & 0xff;
  buf[offset + 3] = (val >>> 24) & 0xff;
}

/**
 * HChaCha20 — derive a 32-byte subkey from a 32-byte key and 16-byte input.
 * Used internally by XChaCha20 to reduce a 24-byte nonce to a 12-byte one.
 */
export function hchacha20(key: Uint8Array | Buffer, input: Uint8Array | Buffer): Buffer {
  // Initial state: constants + key + input
  const state = new Uint32Array(16);
  state[0] = 0x61707865; // "expa"
  state[1] = 0x3320646e; // "nd 3"
  state[2] = 0x79622d32; // "2-by"
  state[3] = 0x6b206574; // "te k"
  for (let i = 0; i < 8; i++) state[4 + i] = readLE32(key, i * 4);
  for (let i = 0; i < 4; i++) state[12 + i] = readLE32(input, i * 4);

  // 20 rounds (10 double-rounds)
  const x = new Uint32Array(state);
  for (let i = 0; i < 10; i++) {
    quarterRound(x, 0, 4, 8, 12);
    quarterRound(x, 1, 5, 9, 13);
    quarterRound(x, 2, 6, 10, 14);
    quarterRound(x, 3, 7, 11, 15);
    quarterRound(x, 0, 5, 10, 15);
    quarterRound(x, 1, 6, 11, 12);
    quarterRound(x, 2, 7, 8, 13);
    quarterRound(x, 3, 4, 9, 14);
  }

  // Output: words 0-3 and 12-15
  const out = Buffer.alloc(32);
  for (let i = 0; i < 4; i++) writeLE32(out, i * 4, x[i]);
  for (let i = 0; i < 4; i++) writeLE32(out, 16 + i * 4, x[12 + i]);
  return out;
}

// ============ Streaming AEAD (matches Monocypher 4 crypto_aead_init_x / write / read) ============

/**
 * Streaming AEAD handler for encrypting/decrypting packets after auth.
 *
 * Internally uses HChaCha20 to derive a subkey, then ChaCha20-Poly1305 IETF
 * with an auto-incrementing counter for each message.
 */
export class StreamingAead {
  private subkey: Buffer;
  private baseNonce: Buffer; // 8 bytes (nonce[16..23])
  private counter: number = 0;

  constructor(key: Uint8Array | Buffer, nonce24: Uint8Array | Buffer) {
    // HChaCha20: derive subkey from key + nonce[0..15]
    this.subkey = hchacha20(key, nonce24.subarray(0, 16));
    // Store nonce[16..23] as base nonce
    this.baseNonce = Buffer.from(nonce24.subarray(16, 24));
  }

  /** Build the 12-byte IETF nonce: LE32(counter) || baseNonce */
  private buildNonce(): Buffer {
    const nonce12 = Buffer.alloc(12);
    writeLE32(nonce12, 0, this.counter);
    this.baseNonce.copy(nonce12, 4);
    return nonce12;
  }

  /** Encrypt a message. Returns MAC (16 bytes) + ciphertext. */
  encrypt(plaintext: Buffer): Buffer {
    const nonce12 = this.buildNonce();
    this.counter++;

    const cipher = crypto.createCipheriv(
      "chacha20-poly1305",
      this.subkey,
      nonce12,
      { authTagLength: 16 }
    );
    // No additional data for packet encryption (OpenTTD uses nullptr)
    const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    const mac = cipher.getAuthTag();
    // Wire format: MAC (16 bytes) + ciphertext
    return Buffer.concat([mac, ciphertext]);
  }

  /** Decrypt a message. Input is MAC (16 bytes) + ciphertext. */
  decrypt(data: Buffer): Buffer {
    if (data.length < X25519_MAC_SIZE) {
      throw new Error(`Encrypted data too short: ${data.length} bytes`);
    }
    const mac = data.subarray(0, X25519_MAC_SIZE);
    const ciphertext = data.subarray(X25519_MAC_SIZE);

    const nonce12 = this.buildNonce();
    this.counter++;

    const decipher = crypto.createDecipheriv(
      "chacha20-poly1305",
      this.subkey,
      nonce12,
      { authTagLength: 16 }
    );
    decipher.setAuthTag(mac);
    const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    return plaintext;
  }
}

/**
 * Perform the full X25519 PAKE auth handshake computation.
 *
 * Given the server's auth request data and the password, returns
 * the auth response bytes and encryption handlers.
 */
export function computePakeResponse(
  serverPublicKey: Uint8Array,
  keyExchangeNonce: Uint8Array,
  password: string
): {
  clientPublicKey: Uint8Array;
  mac: Buffer;
  encryptedMessage: Buffer;
  clientToServerKey: Buffer;
  serverToClientKey: Buffer;
} {
  // Make independent copies of inputs to avoid Buffer view/byteOffset issues
  const serverPubKey = new Uint8Array(serverPublicKey);
  const nonce = new Uint8Array(keyExchangeNonce);

  // Generate client keypair
  const { secretKey, publicKey: clientPublicKey } = generateX25519Keypair();

  // X25519 shared secret (libsodium returns independent Uint8Array)
  const sharedSecret = x25519SharedSecret(secretKey, serverPubKey);

  // Derive keys with password
  const { clientToServer, serverToClient } = deriveKeys(
    sharedSecret,
    serverPubKey,
    clientPublicKey,
    password
  );

  // Generate 8 random bytes and encrypt with XChaCha20-Poly1305
  const randomMessage = Buffer.from(sodium.randombytes_buf(X25519_KEY_EXCHANGE_MESSAGE_SIZE));
  const { ciphertext, mac } = aeadEncrypt(
    clientToServer,
    nonce,
    randomMessage,
    clientPublicKey // additional data = our public key
  );

  return {
    clientPublicKey,
    mac,
    encryptedMessage: ciphertext,
    clientToServerKey: clientToServer,
    serverToClientKey: serverToClient,
  };
}
