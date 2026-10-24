// Checks the browser side of key custody against the Ruby side.
// Run with: bun test spec/javascript
import { describe, expect, test } from "bun:test"
import { combine } from "shamir-secret-sharing"
import vectors from "../fixtures/files/key_custody/browser_vectors.json"
import {
  b64Decode, b64Encode, b64urlDecode, b64urlEncode, deriveSealKey, generateMasterKey, openSealedShare, sealAad,
  sealShare, shareDigest, splitKey
} from "../../app/javascript/key_custody/crypto"

// Some runtimes (for example bun 1.2) have no X25519 in WebCrypto. The
// browsers the key holders use do (Chrome 133+, Firefox 130+, Safari 17+),
// and so does Node 22, which made the browser_sealed vector.
const supportsX25519 = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]).then(() => true, () => false)

describe("key custody browser crypto", () => {
  test("computes the same share digest as Ruby", async () => {
    const vector = vectors.digest
    expect(await shareDigest(b64urlDecode(vector.share), b64Decode(vector.public_key))).toBe(vector.hex)
  })

  test("builds the same sealed-share aad as Ruby", () => {
    expect(sealAad("cHVibGlj", "usr_x", "cred_y", 7)).toBe("weave key custody sealed share v1|cHVibGlj|usr_x|cred_y|7")
    expect(vectors.ruby_sealed.aad).toMatch(/^weave key custody sealed share v1\|/)
  })

  test.skipIf(!supportsX25519)("derives the same seal public key from a PRF output as Ruby", async () => {
    const { publicKey } = await deriveSealKey(b64urlDecode(vectors.seal_key.prf))
    expect(b64Encode(publicKey)).toBe(vectors.seal_key.seal_public_key)
  })

  test.skipIf(!supportsX25519)("opens a share that Ruby sealed, and refuses another aad or PRF output", async () => {
    const vector = vectors.ruby_sealed
    const share = await openSealedShare(b64urlDecode(vector.prf), vector)
    expect(b64urlEncode(share)).toBe(vector.share)
    await expect(openSealedShare(b64urlDecode(vector.prf), { ...vector, aad: `${vector.aad}x` })).rejects.toThrow()
    await expect(openSealedShare(crypto.getRandomValues(new Uint8Array(32)), vector)).rejects.toThrow()
  })

  test.skipIf(!supportsX25519)("round-trips a seal to a seal public key", async () => {
    const prf = crypto.getRandomValues(new Uint8Array(32))
    const { publicKey } = await deriveSealKey(prf)
    const share = crypto.getRandomValues(new Uint8Array(33))
    const aad = sealAad("cHVibGlj", "usr_x", "cred_y", share[32])
    const sealed = await sealShare(publicKey, share, aad)
    expect(b64urlDecode(sealed).length).toBe(1 + 32 + 12 + 33 + 16)
    expect(await openSealedShare(prf, { sealed, aad })).toEqual(share)
  })

  test.skipIf(!supportsX25519)("makes a 32-byte X25519 key pair and splits it 2-of-3", async () => {
    const { privateKey, publicKey } = await generateMasterKey()
    expect(privateKey.length).toBe(32)
    expect(publicKey.length).toBe(32)
    expect(b64Decode(b64Encode(publicKey))).toEqual(publicKey)
    const shares = await splitKey(privateKey, 3, 2)
    expect(shares.map((share) => share.length)).toEqual([33, 33, 33])
    for (const pair of [[0, 1], [0, 2], [1, 2]]) {
      expect(await combine(pair.map((index) => shares[index]))).toEqual(privateKey)
    }
  })
})
