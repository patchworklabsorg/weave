// WebAuthn calls for key custody, with the PRF extension. The options come
// from Weave as JSON with Base64url values. The answer goes back as JSON,
// without the PRF output: the PRF output stays on this page.
import { b64Encode, b64urlDecode, b64urlEncode, deriveSealKey, wipe } from "./crypto"

function prfInputs(evalByCredential) {
  const result = {}
  Object.entries(evalByCredential || {}).forEach(([id, salts]) => {
    result[id] = { first: b64urlDecode(salts.first) }
    if (salts.second) result[id].second = b64urlDecode(salts.second)
  })
  return result
}

// Calls navigator.credentials.get. allow limits the keys (for example one
// key at a time in the ceremony). Returns { credential (JSON for Weave),
// id, prf: { first, second } }.
export async function getAssertion(options, { allow, prf } = {}) {
  const allowCredentials = (allow || options.allowCredentials).map((item) => ({
    type: "public-key",
    id: b64urlDecode(item.id)
  }))
  const evalByCredential = prf || options.extensions?.prf?.evalByCredential
  const publicKey = {
    challenge: b64urlDecode(options.challenge),
    rpId: options.rpId,
    timeout: options.timeout,
    userVerification: options.userVerification,
    allowCredentials,
    extensions: evalByCredential ? { prf: { evalByCredential: prfInputs(evalByCredential) } } : {}
  }
  const assertion = await navigator.credentials.get({ publicKey })
  const results = assertion.getClientExtensionResults().prf?.results
  if (evalByCredential && !results?.first) throw new Error("This hardware key gave no PRF output. Use a key with hmac-secret.")

  return {
    id: assertion.id,
    prf: results ? { first: new Uint8Array(results.first), second: results.second && new Uint8Array(results.second) } : {},
    credential: {
      type: assertion.type,
      id: assertion.id,
      rawId: b64urlEncode(assertion.rawId),
      authenticatorAttachment: assertion.authenticatorAttachment,
      clientExtensionResults: {},
      response: {
        clientDataJSON: b64urlEncode(assertion.response.clientDataJSON),
        authenticatorData: b64urlEncode(assertion.response.authenticatorData),
        signature: b64urlEncode(assertion.response.signature),
        userHandle: assertion.response.userHandle ? b64urlEncode(assertion.response.userHandle) : null
      }
    }
  }
}

// The registration options for navigator.credentials.create, with the PRF
// seal salt as bytes (extensions.prf.eval.first).
export function creationPublicKey(options) {
  const { seal_salt: _sealSalt, ...rest } = options
  const publicKey = {
    ...rest,
    challenge: b64urlDecode(options.challenge),
    user: { ...options.user, id: b64urlDecode(options.user.id) },
    excludeCredentials: options.excludeCredentials.map((item) => ({ type: "public-key", id: b64urlDecode(item.id) }))
  }
  const first = options.extensions?.prf?.eval?.first
  publicKey.extensions = { ...options.extensions, prf: first ? { eval: { first: b64urlDecode(first) } } : {} }
  return publicKey
}

// Calls navigator.credentials.create for a new hardware key. Returns
// { credential (JSON for Weave), prfFirst }. prfFirst is the PRF output for
// the seal salt when the key gave it at creation (one touch), or null.
export async function createCredential(options, credentials = navigator.credentials) {
  const credential = await credentials.create({ publicKey: creationPublicKey(options) })
  const prf = credential.getClientExtensionResults().prf
  const first = prf?.results?.first
  return { credential: credentialJSON(credential, prf), prfFirst: first ? new Uint8Array(first) : null }
}

function credentialJSON(credential, prf) {
  return {
    type: credential.type,
    id: credential.id,
    rawId: b64urlEncode(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    clientExtensionResults: { prf: { enabled: prf?.enabled === true } },
    response: {
      clientDataJSON: b64urlEncode(credential.response.clientDataJSON),
      attestationObject: b64urlEncode(credential.response.attestationObject),
      transports: credential.response.getTransports ? credential.response.getTransports() : []
    }
  }
}

// The enrollment request body for Weave. A key without PRF is refused. When
// the key gave its PRF output at creation (one touch), the seal public key
// goes with the registration, and the PRF output is wiped. Otherwise the body
// has no seal key, and Weave answers with the options of the second touch.
export async function enrollmentBody(created, { role, nickname }, derive = deriveSealKey) {
  if (created.credential.clientExtensionResults?.prf?.enabled !== true) {
    throw new Error("This key has no PRF (hmac-secret) support, so it can't hold a share. Use a YubiKey 5 with firmware 5.2 or later.")
  }
  const body = { credential: created.credential, role, nickname }
  if (created.prfFirst) {
    try {
      const { publicKey } = await derive(created.prfFirst)
      body.seal_public_key = b64Encode(publicKey)
    } finally {
      wipe(created.prfFirst)
    }
  }
  return body
}
