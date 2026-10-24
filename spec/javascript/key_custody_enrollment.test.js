// Checks the two enrollment paths in the browser (see
// app/javascript/key_custody/webauthn.js): one touch when the key gives its
// PRF output at creation, two touches when it does not.
// Run with: bun test spec/javascript
import { describe, expect, test } from "bun:test"
import { b64urlEncode } from "../../app/javascript/key_custody/crypto"
import { createCredential, creationPublicKey, enrollmentBody } from "../../app/javascript/key_custody/webauthn"

const salt = new Uint8Array(32).fill(7)
const options = {
  challenge: b64urlEncode(new Uint8Array([1, 2, 3])),
  rp: { id: "localhost", name: "Weave" },
  user: { id: b64urlEncode(new Uint8Array([9])), name: "holder@example.com", displayName: "Holder" },
  pubKeyCredParams: [{ type: "public-key", alg: -7 }],
  excludeCredentials: [],
  extensions: { prf: { eval: { first: b64urlEncode(salt) } } },
  seal_salt: b64urlEncode(salt)
}

// A fake navigator.credentials whose key gives prfResults at creation.
function fakeCredentials({ enabled = true, first = null } = {}) {
  const seen = {}
  return {
    seen,
    async create({ publicKey }) {
      seen.publicKey = publicKey
      return {
        type: "public-key",
        id: "cred",
        rawId: new Uint8Array([4]).buffer,
        authenticatorAttachment: "cross-platform",
        getClientExtensionResults: () => ({ prf: first ? { enabled, results: { first: first.buffer } } : { enabled } }),
        response: {
          clientDataJSON: new Uint8Array([5]).buffer,
          attestationObject: new Uint8Array([6]).buffer,
          getTransports: () => ["usb"]
        }
      }
    }
  }
}

const fakeDerive = async (prf) => ({ publicKey: new Uint8Array(32).fill(prf[0]) })

describe("key custody enrollment", () => {
  test("asks for PRF at creation on the seal salt, as bytes", () => {
    const publicKey = creationPublicKey(options)
    expect(publicKey.extensions.prf.eval.first).toEqual(salt)
    expect(publicKey.seal_salt).toBeUndefined()
  })

  test("one touch: sends the seal public key with the registration and wipes the PRF output", async () => {
    const credentials = fakeCredentials({ first: new Uint8Array(32).fill(3) })
    const created = await createCredential(options, credentials)
    expect(created.prfFirst).toEqual(new Uint8Array(32).fill(3))
    expect(created.credential.clientExtensionResults).toEqual({ prf: { enabled: true } })

    const body = await enrollmentBody(created, { role: "primary", nickname: "" }, fakeDerive)

    expect(body.seal_public_key).toBe(btoa(String.fromCharCode(...new Uint8Array(32).fill(3))))
    expect(created.prfFirst.every((byte) => byte === 0)).toBe(true)
    expect(JSON.stringify(body.credential)).not.toContain("results")
  })

  test("two touches: no PRF output at creation, so no seal key in the registration", async () => {
    const created = await createCredential(options, fakeCredentials())
    expect(created.prfFirst).toBeNull()

    const body = await enrollmentBody(created, { role: "backup", nickname: "Old key" }, fakeDerive)

    expect(body).toEqual({ credential: created.credential, role: "backup", nickname: "Old key" })
  })

  test("refuses a key whose PRF is not enabled", async () => {
    const created = await createCredential(options, fakeCredentials({ enabled: false }))
    await expect(enrollmentBody(created, { role: "primary", nickname: "" }, fakeDerive)).rejects.toThrow(/PRF/)
  })
})
