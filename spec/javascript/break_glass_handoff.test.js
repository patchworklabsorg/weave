// Checks the browser side of the sealed break-glass handoff against Ruby.
// Run with: bun test spec/javascript
//
// Bun 1.2 has no X25519 in WebCrypto, so the X25519 tests skip there. The
// browsers do, and so does Node 22. To run the full check with Node:
//   node spec/javascript/break_glass_handoff_node_check.mjs
import { describe, expect, test } from "bun:test"
import vectors from "../fixtures/files/key_custody/handoff_vectors.json"
import { b64Decode } from "../../app/javascript/key_custody/crypto"
import { decryptImage, generateHandoffKeyPair, openSealedDataKey } from "../../app/javascript/key_custody/handoff"

const supportsX25519 = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]).then(() => true, () => false)

// The PKCS #8 header of a raw X25519 private key (RFC 8410).
const PKCS8_PREFIX = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20])

async function vectorPrivateKey() {
  const raw = b64Decode(vectors.private_key)
  const pkcs8 = new Uint8Array(PKCS8_PREFIX.length + raw.length)
  pkcs8.set(PKCS8_PREFIX)
  pkcs8.set(raw, PKCS8_PREFIX.length)
  // Not extractable, like the key the browser keeps in IndexedDB.
  return crypto.subtle.importKey("pkcs8", pkcs8, { name: "X25519" }, false, ["deriveBits"])
}

describe("sealed break-glass handoff in the browser", () => {
  test("decrypts an image that Ruby encrypted, and refuses another aad", async () => {
    const image = await decryptImage(b64Decode(vectors.data_key), b64Decode(vectors.ciphertext), vectors.image_aad)
    expect(Array.from(image)).toEqual(Array.from(b64Decode(vectors.image)))
    await expect(decryptImage(b64Decode(vectors.data_key), b64Decode(vectors.ciphertext), "verification:43")).rejects.toThrow()
  })

  test.skipIf(!supportsX25519)("makes a one-time key pair whose private key can't be exported", async () => {
    const pair = await generateHandoffKeyPair()
    expect(pair.publicKey.length).toBe(32)
    expect(pair.privateKey.extractable).toBe(false)
    await expect(crypto.subtle.exportKey("pkcs8", pair.privateKey)).rejects.toThrow()
  })

  test.skipIf(!supportsX25519)("opens a data key that Ruby sealed to the browser key, and refuses another aad or key", async () => {
    const privateKey = await vectorPrivateKey()
    const publicKey = b64Decode(vectors.public_key)
    const dataKey = await openSealedDataKey(privateKey, publicKey, b64Decode(vectors.sealed_key), vectors.handoff_aad)
    expect(Array.from(dataKey)).toEqual(Array.from(b64Decode(vectors.data_key)))
    await expect(openSealedDataKey(privateKey, publicKey, b64Decode(vectors.sealed_key), `${vectors.handoff_aad}x`)).rejects.toThrow()
    const other = await generateHandoffKeyPair()
    await expect(openSealedDataKey(other.privateKey, other.publicKey, b64Decode(vectors.sealed_key), vectors.handoff_aad)).rejects.toThrow()
  })
})
