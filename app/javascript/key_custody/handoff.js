// The browser side of the sealed break-glass handoff (see BreakGlass and
// docs/KYC.md, "The sealed handoff").
//
// - When a person asks for break-glass, this browser makes a one-time X25519
//   key pair. The private key is a NON-EXTRACTABLE CryptoKey, kept in
//   IndexedDB under the request id. Only the public key goes to Weave.
// - The second approval seals the image's data key to that public key
//   (KeyCustody::Crypto.seal with HANDOFF_INFO). Weave can't open it.
// - Open: this browser opens the sealed data key with the private key,
//   decrypts the image (AES-256-GCM, KeyCustody::Crypto.encrypt), and then
//   deletes the private key.
//
// The server side of the formats is app/services/key_custody/crypto.rb.

const encoder = new TextEncoder()
const HANDOFF_INFO = "weave key custody handoff v1"
const SEAL_AAD_PREFIX = "weave key custody seal v1|"
const SEAL_VERSION = 1
const DATA_VERSION = 1
const DB_NAME = "weave-break-glass"
const STORE = "handoff-keys"

function concat(...arrays) {
  const out = new Uint8Array(arrays.reduce((sum, array) => sum + array.length, 0))
  let offset = 0
  arrays.forEach((array) => { out.set(array, offset); offset += array.length })
  return out
}

// A one-time key pair. The private key can't be exported, also not by this
// page. Returns { privateKey (CryptoKey), publicKey (raw bytes) }.
export async function generateHandoffKeyPair() {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, false, ["deriveBits"])
  const publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey))
  return { privateKey: pair.privateKey, publicKey }
}

// Opens a data key sealed to this browser's key pair:
//   version (1) | ephemeral public key (32) | nonce (12) | ciphertext | tag (16)
export async function openSealedDataKey(privateKey, publicKey, sealed, aad) {
  if (sealed[0] !== SEAL_VERSION) throw new Error("Unknown seal version.")
  const ephemeralPublic = sealed.slice(1, 33)
  const nonce = sealed.slice(33, 45)
  const ephemeral = await crypto.subtle.importKey("raw", ephemeralPublic, { name: "X25519" }, true, [])
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: ephemeral }, privateKey, 256))
  const base = await crypto.subtle.importKey("raw", shared, "HKDF", false, ["deriveKey"])
  shared.fill(0)
  const key = await crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt: concat(ephemeralPublic, publicKey), info: encoder.encode(HANDOFF_INFO) },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["decrypt"]
  )
  const dataKey = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce, additionalData: encoder.encode(SEAL_AAD_PREFIX + aad) },
    key,
    sealed.slice(45)
  )
  return new Uint8Array(dataKey)
}

// Decrypts an image that KeyCustody::Crypto.encrypt made:
//   version (1) | nonce (12) | ciphertext | tag (16)
// The data key is imported as non-extractable, and the caller wipes it.
export async function decryptImage(dataKey, blob, aad) {
  if (blob[0] !== DATA_VERSION) throw new Error("Unknown data version.")
  const key = await crypto.subtle.importKey("raw", dataKey, { name: "AES-GCM" }, false, ["decrypt"])
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: blob.slice(1, 13), additionalData: encoder.encode(aad) },
    key,
    blob.slice(13)
  )
  return new Uint8Array(plaintext)
}

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE)
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

async function withStore(mode, action) {
  const db = await openDatabase()
  try {
    return await new Promise((resolve, reject) => {
      const transaction = db.transaction(STORE, mode)
      const request = action(transaction.objectStore(STORE))
      transaction.oncomplete = () => resolve(request?.result)
      transaction.onerror = () => reject(transaction.error)
      transaction.onabort = () => reject(transaction.error)
    })
  } finally {
    db.close()
  }
}

// Keeps the key pair under the request id. A CryptoKey is stored as it is:
// IndexedDB keeps it non-extractable.
export function storeHandoffKey(requestId, pair) {
  return withStore("readwrite", (store) => store.put({ privateKey: pair.privateKey, publicKey: pair.publicKey }, requestId))
}

export function loadHandoffKey(requestId) {
  return withStore("readonly", (store) => store.get(requestId))
}

export function deleteHandoffKey(requestId) {
  return withStore("readwrite", (store) => store.delete(requestId))
}
