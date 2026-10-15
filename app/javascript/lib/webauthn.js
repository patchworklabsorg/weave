// Helpers for the passkey Stimulus controllers. The server sends WebAuthn
// options as JSON with base64url strings (the webauthn gem's format), and the
// browser API takes and gives ArrayBuffers, so these convert both ways. They do
// not use PublicKeyCredential.parse*OptionsFromJSON, because older Safari
// versions do not have it.

export function passkeysSupported() {
  return typeof window.PublicKeyCredential === "function" && !!navigator.credentials
}

export async function conditionalMediationAvailable() {
  if (!passkeysSupported() || typeof PublicKeyCredential.isConditionalMediationAvailable !== "function") {
    return false
  }

  try {
    return await PublicKeyCredential.isConditionalMediationAvailable()
  } catch {
    return false
  }
}

export async function fetchOptions(url) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
    },
    credentials: "same-origin"
  })

  if (!response.ok) throw new Error(`Passkey options request failed (${response.status})`)

  return response.json()
}

export function creationOptions(json) {
  return {
    ...json,
    challenge: toBuffer(json.challenge),
    user: { ...json.user, id: toBuffer(json.user.id) },
    excludeCredentials: (json.excludeCredentials || []).map(descriptor)
  }
}

export function requestOptions(json) {
  return {
    ...json,
    challenge: toBuffer(json.challenge),
    allowCredentials: (json.allowCredentials || []).map(descriptor)
  }
}

export function serializeAttestation(credential) {
  return JSON.stringify({
    type: credential.type,
    id: credential.id,
    rawId: toBase64Url(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    clientExtensionResults: credential.getClientExtensionResults(),
    response: {
      clientDataJSON: toBase64Url(credential.response.clientDataJSON),
      attestationObject: toBase64Url(credential.response.attestationObject),
      transports: credential.response.getTransports?.() || []
    }
  })
}

export function serializeAssertion(credential) {
  const response = credential.response

  return JSON.stringify({
    type: credential.type,
    id: credential.id,
    rawId: toBase64Url(credential.rawId),
    authenticatorAttachment: credential.authenticatorAttachment,
    clientExtensionResults: credential.getClientExtensionResults(),
    response: {
      clientDataJSON: toBase64Url(response.clientDataJSON),
      authenticatorData: toBase64Url(response.authenticatorData),
      signature: toBase64Url(response.signature),
      userHandle: response.userHandle ? toBase64Url(response.userHandle) : null
    }
  })
}

// A message for the person, from a WebAuthn DOMException.
export function errorMessage(error) {
  switch (error?.name) {
    case "NotAllowedError":
      return "The passkey request was cancelled or timed out."
    case "InvalidStateError":
      return "This device already has a passkey for your account."
    case "NotSupportedError":
      return "This device can't use passkeys."
    case "SecurityError":
      return "Passkeys can't be used on this address."
    default:
      return "Something went wrong with the passkey. Try again."
  }
}

function descriptor(item) {
  return { ...item, id: toBuffer(item.id) }
}

function toBuffer(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function toBase64Url(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
