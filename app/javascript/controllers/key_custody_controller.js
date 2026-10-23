// The key custody actions in the browser (see KeyCustody and docs/KYC.md):
// enroll a hardware key and set up its seal key, approve a break-glass
// request with a share, run the ceremony, activate a key set, and seal a
// share for a new key.
//
// Each holder works on their own computer. A share is opened here with the
// seal key of the holder's hardware key (from its PRF output) and sent to
// Weave only for an approval or an activation, over the signed-in session,
// with a WebAuthn answer for that one request. The PRF output, the seal
// private key and the master private key never leave this page.
import { Controller } from "@hotwired/stimulus"
import {
  b64Decode, b64Encode, b64urlEncode, deriveSealKey, generateMasterKey, openSealedShare, sealAad, sealShare,
  shareDigest, splitKey, wipe
} from "../key_custody/crypto"
import { createCredential, enrollmentBody, getAssertion } from "../key_custody/webauthn"

export default class extends Controller {
  static targets = ["status", "role", "nickname", "log"]
  static values = { optionsUrl: String, submitUrl: String, redirectUrl: String }

  // Enroll a hardware key for the signed-in key holder. A key that gives
  // its PRF output at creation sends its seal key in the same request (one
  // touch). Otherwise touch it again to set up its seal key.
  async enroll(event) {
    event.preventDefault()
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      this.say("Touch the new hardware key and enter its PIN.")
      const created = await createCredential(options)
      const enrolled = await this.post(this.submitUrlValue, await enrollmentBody(created, {
        role: this.hasRoleTarget ? this.roleTarget.value : "primary",
        nickname: this.hasNicknameTarget ? this.nicknameTarget.value : ""
      }))
      this.say(enrolled.message)
      if (enrolled.one_touch) return enrolled
      return this.sendSealKey(enrolled.seal, enrolled.seal_url)
    })
  }

  // Set up the seal key of a key that was enrolled without one.
  async registerSealKey(event) {
    event.preventDefault()
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      return this.sendSealKey(options, this.submitUrlValue)
    })
  }

  // One touch with PRF on the key's seal salt. Only the seal public key and
  // the WebAuthn answer go to Weave.
  async sendSealKey(options, url) {
    this.say("Touch the same hardware key again and enter its PIN.")
    const assertion = await getAssertion(options)
    const { publicKey } = await deriveSealKey(assertion.prf.first)
    wipe(assertion.prf.first)
    return this.post(url, { credential: assertion.credential, seal_public_key: b64Encode(publicKey) })
  }

  // Opens the share that this key's seal key opens, and checks its digest.
  async openShare(assertion, wrapped, publicKeyBase64, digest) {
    const share = await openSealedShare(assertion.prf.first, wrapped)
    if (digest && await shareDigest(share, b64Decode(publicKeyBase64)) !== digest) {
      wipe(share)
      throw new Error("The opened share does not match your share on record.")
    }
    return share
  }

  // Approve a break-glass request: open the share with a hardware key and
  // send it with an answer bound to this request. The approver never gets
  // the image: the second share seals it to the requester's browser.
  async approve(event) {
    event.preventDefault()
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      this.say("Touch one of your hardware keys and enter its PIN.")
      const assertion = await getAssertion(options.request)
      let share = null
      try {
        share = await this.openShare(assertion, options.wrapped[assertion.id], options.public_key, options.digest)
        return await this.post(this.submitUrlValue, { credential: assertion.credential, share: b64urlEncode(share) }, "PATCH")
      } finally {
        wipe(share, assertion.prf.first)
      }
    })
  }

  // The ceremony: one holder runs it on a clean computer. The master key
  // and the shares exist only in this page's memory, until the end of this
  // function. Each share is sealed to its holder's seal public keys, so no
  // other holder's key touches this computer. The operator touches only
  // their own key, once.
  async ceremony(event) {
    event.preventDefault()
    let privateKey = null
    let shares = []
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      const master = await generateMasterKey()
      privateKey = master.privateKey
      const publicKey = b64Encode(master.publicKey)
      shares = await splitKey(privateKey, options.share_count, options.threshold)
      wipe(privateKey)
      this.log(`Made a master key pair and ${options.share_count} shares. Any ${options.threshold} rebuild the key.`)

      const entries = []
      for (const [index, holder] of options.holders.entries()) {
        const share = shares[index]
        const x = share[share.length - 1]
        const wrapped = []
        for (const key of holder.keys) {
          const sealed = await sealShare(b64Decode(key.seal_public_key), share, sealAad(publicKey, holder.id, key.id, x))
          wrapped.push({ credential_id: key.id, sealed })
          this.log(`Sealed the share of ${holder.name} for "${key.label}".`)
        }
        entries.push({ holder_id: holder.id, x, digest: await shareDigest(share, master.publicKey), wrapped })
      }
      shares.forEach((share) => wipe(share))
      this.say("Touch your own hardware key and enter its PIN to finish. This touch also gives your activation share.")
      const assertion = await getAssertion(options.request)
      // One touch: the PRF output of this assertion opens the operator's own
      // just-sealed share, which Weave takes as the operator's activation
      // share. Without PRF the operator activates later, like the others.
      let operatorShare = null
      try {
        operatorShare = await this.openOperatorShare(assertion, entries, options.operator_id, publicKey)
        return await this.post(this.submitUrlValue, {
          ceremony: options.ceremony, public_key: publicKey, shares: entries, credential: assertion.credential,
          operator_share: operatorShare && b64urlEncode(operatorShare)
        })
      } finally {
        wipe(operatorShare, assertion.prf.first)
      }
    })
    wipe(privateKey, ...shares)
  }

  // The operator's own share, opened from the copy just sealed to the key
  // that signed the assertion. Null when the key gave no PRF output.
  async openOperatorShare(assertion, entries, operatorId, publicKey) {
    if (!assertion.prf.first) return null
    const entry = entries.find((item) => item.holder_id === operatorId)
    const wrapped = entry?.wrapped.find((item) => item.credential_id === assertion.id)
    if (!wrapped) return null
    return openSealedShare(assertion.prf.first, {
      sealed: wrapped.sealed, aad: sealAad(publicKey, operatorId, wrapped.credential_id, entry.x)
    })
  }

  // Activate a pending key set with the new share (and, for a rotation,
  // the old share). One touch: the key's seal key opens both.
  async activate(event) {
    event.preventDefault()
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      this.say("Touch one of your hardware keys and enter its PIN.")
      const assertion = await getAssertion(options.request)
      const boxes = options.wrapped[assertion.id]
      let newShare = null
      let oldShare = null
      try {
        if (boxes.new) newShare = await openSealedShare(assertion.prf.first, boxes.new)
        if (boxes.old) oldShare = await openSealedShare(assertion.prf.first, boxes.old)
        return await this.post(this.submitUrlValue, {
          credential: assertion.credential,
          new_share: newShare && b64urlEncode(newShare),
          old_share: oldShare && b64urlEncode(oldShare)
        })
      } finally {
        wipe(newShare, oldShare, assertion.prf.first)
      }
    })
  }

  // Seal the share for a new key: open it with a remaining key, seal it to
  // the new key's seal public key. The share is not sent to Weave, and the
  // new key needs no touch.
  async rewrap(event) {
    event.preventDefault()
    await this.run(async () => {
      const options = await this.post(this.optionsUrlValue, {})
      this.say("Touch the hardware key you still have.")
      const old = await getAssertion(options.old)
      let share = null
      try {
        share = await this.openShare(old, options.old.wrapped[old.id], options.public_key, options.digest)
        const sealed = await sealShare(b64Decode(options.new.seal_public_key), share, options.new.aad)
        return await this.post(this.submitUrlValue, { old_credential: old.credential, sealed })
      } finally {
        wipe(share, old.prf.first)
      }
    })
  }

  async run(step) {
    try {
      const result = await step()
      this.say(result.message || "Done.")
      window.location.assign(result.redirect || this.redirectUrlValue || window.location.href)
    } catch (error) {
      this.say(`Stopped: ${error.message}`)
    }
  }

  async post(url, body, method = "POST") {
    return this.request(url, { method, body: JSON.stringify(body) })
  }

  async request(url, init) {
    const response = await fetch(url, {
      ...init,
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      }
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(data.error || `The server answered ${response.status}.`)
    return data
  }

  say(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  log(message) {
    if (!this.hasLogTarget) return
    const item = document.createElement("li")
    item.textContent = message
    this.logTarget.appendChild(item)
  }
}
