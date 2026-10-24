// The browser side of key custody (see KeyCustody and docs/KYC.md).
//
// - The ceremony makes the master key pair (X25519) and splits the private
//   key with the audited "shamir-secret-sharing" library. Weave gets only
//   the public key and the sealed shares.
// - Each hardware key has a seal key pair: HKDF-SHA256 of its PRF output
//   gives an X25519 private key, on the holder's own computer. Weave stores
//   only the public key.
// - The ceremony seals each share to its holder's seal public keys (X25519
//   + HKDF-SHA256 + AES-256-GCM). The holder opens it on their own computer
//   with one touch. The PRF output never leaves the page that asked for it.
//
// The server side of the same formats is app/services/key_custody/crypto.rb
// and spec/support/key_custody_helpers.rb.
import { split } from "shamir-secret-sharing"

const encoder = new TextEncoder()
const SEAL_KEY_INFO = "weave key custody seal key v1"
const SHARE_SEAL_INFO = "weave key custody sealed share v1"
const SEAL_AAD_PREFIX = "weave key custody seal v1|"
const SEAL_VERSION = 1
const DIGEST_PREFIX = "weave key custody share v1\0"

export function b64urlEncode(bytes) {
  const array = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  let binary = ""
  array.forEach((byte) => { binary += String.fromCharCode(byte) })
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

export function b64urlDecode(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64 + "===".slice((base64.length + 3) % 4)
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0))
}

export function b64Encode(bytes) {
  const value = b64urlEncode(bytes).replace(/-/g, "+").replace(/_/g, "/")
  return value + "=".repeat((4 - (value.length % 4)) % 4)
}

export function b64Decode(value) {
  return b64urlDecode(value.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""))
}

// Overwrites byte arrays in place. JavaScript can keep other copies (the
// garbage collector, WebCrypto), so this is best effort.
export function wipe(...arrays) {
  arrays.forEach((array) => { if (array instanceof Uint8Array) array.fill(0) })
}

function concat(...arrays) {
  const out = new Uint8Array(arrays.reduce((sum, array) => sum + array.length, 0))
  let offset = 0
  arrays.forEach((array) => { out.set(array, offset); offset += array.length })
  return out
}

async function hkdfBits(secret, salt, info) {
  const base = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"])
  const bits = await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info: encoder.encode(info) }, base, 256)
  return new Uint8Array(bits)
}

async function hkdfAesKey(secret, salt, info) {
  const base = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveKey"])
  return crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt, info: encoder.encode(info) },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  )
}

// The PKCS #8 header of a raw X25519 private key (RFC 8410).
const X25519_PKCS8_PREFIX = Uint8Array.from([
  0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20
])

// The seal key pair of a hardware key: HKDF-SHA256 of its PRF output gives
// the X25519 private key. Only the public key leaves this page (at
// enrollment). The same steps in Ruby: KeyCustody::Crypto.seal_private_key.
export async function deriveSealKey(prfOutput) {
  const raw = await hkdfBits(prfOutput, new Uint8Array(0), SEAL_KEY_INFO)
  const pkcs8 = concat(X25519_PKCS8_PREFIX, raw)
  wipe(raw)
  const privateKey = await crypto.subtle.importKey("pkcs8", pkcs8, { name: "X25519" }, true, ["deriveBits"])
  wipe(pkcs8)
  const jwk = await crypto.subtle.exportKey("jwk", privateKey)
  return { privateKey, publicKey: b64urlDecode(jwk.x) }
}

async function shareKey(shared, ephemeralPublic, recipientPublic) {
  const key = await hkdfAesKey(shared, concat(ephemeralPublic, recipientPublic), SHARE_SEAL_INFO)
  wipe(shared)
  return key
}

// Seals a share to a hardware key's seal public key (X25519 + HKDF-SHA256 +
// AES-256-GCM). The format is KeyCustody::Crypto.seal:
//   version (1) | ephemeral public key (32) | nonce (12) | ciphertext | tag (16)
// Returns Base64url.
export async function sealShare(sealPublicKey, share, aad) {
  const ephemeral = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"])
  const ephemeralPublic = new Uint8Array(await crypto.subtle.exportKey("raw", ephemeral.publicKey))
  const recipient = await crypto.subtle.importKey("raw", sealPublicKey, { name: "X25519" }, true, [])
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: recipient }, ephemeral.privateKey, 256))
  const key = await shareKey(shared, ephemeralPublic, sealPublicKey)
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const body = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: encoder.encode(SEAL_AAD_PREFIX + aad) },
    key,
    share
  )
  return b64urlEncode(concat(Uint8Array.of(SEAL_VERSION), ephemeralPublic, nonce, new Uint8Array(body)))
}

// Opens a sealed share ({ sealed, aad }) with the seal key of the hardware
// key that gave this PRF output.
export async function openSealedShare(prfOutput, wrapped) {
  const { privateKey, publicKey } = await deriveSealKey(prfOutput)
  const blob = b64urlDecode(wrapped.sealed)
  if (blob[0] !== SEAL_VERSION) throw new Error("Unknown seal version.")
  const ephemeralPublic = blob.slice(1, 33)
  const nonce = blob.slice(33, 45)
  const ephemeral = await crypto.subtle.importKey("raw", ephemeralPublic, { name: "X25519" }, true, [])
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: ephemeral }, privateKey, 256))
  const key = await shareKey(shared, ephemeralPublic, publicKey)
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce, additionalData: encoder.encode(SEAL_AAD_PREFIX + wrapped.aad) },
    key,
    blob.slice(45)
  )
  return new Uint8Array(plaintext)
}

// SHA-256 of the share, bound to the key set, as hex. Weave stores it to
// refuse a wrong share.
export async function shareDigest(share, publicKey) {
  const prefix = encoder.encode(DIGEST_PREFIX)
  const input = new Uint8Array(prefix.length + publicKey.length + share.length)
  input.set(prefix, 0)
  input.set(publicKey, prefix.length)
  input.set(share, prefix.length + publicKey.length)
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", input))
  wipe(input)
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("")
}

// A new X25519 master key pair, as raw bytes.
export async function generateMasterKey() {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"])
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey)
  return { privateKey: b64urlDecode(jwk.d), publicKey: b64urlDecode(jwk.x) }
}

export async function splitKey(privateKey, shareCount, threshold) {
  return split(privateKey, shareCount, threshold)
}

// The additional data of a sealed share (KeyCustodyWrappedShare.aad).
export function sealAad(publicKeyBase64, holderId, credentialId, x) {
  return `weave key custody sealed share v1|${publicKeyBase64}|${holderId}|${credentialId}|${x}`
}
