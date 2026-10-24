// The X25519 half of break_glass_handoff.test.js, for Node 22 (bun has no
// X25519). Run: node spec/javascript/break_glass_handoff_node_check.mjs
import { readFileSync } from "node:fs"
import { decryptImage, generateHandoffKeyPair, openSealedDataKey } from "../../app/javascript/key_custody/handoff.js"

const vectors = JSON.parse(readFileSync(new URL("../fixtures/files/key_custody/handoff_vectors.json", import.meta.url)))
const b64 = (value) => Uint8Array.from(Buffer.from(value, "base64"))
const prefix = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20])
const privateKey = await crypto.subtle.importKey("pkcs8", Buffer.concat([prefix, b64(vectors.private_key)]), { name: "X25519" }, false, ["deriveBits"])

const dataKey = await openSealedDataKey(privateKey, b64(vectors.public_key), b64(vectors.sealed_key), vectors.handoff_aad)
if (Buffer.compare(Buffer.from(dataKey), Buffer.from(b64(vectors.data_key))) !== 0) throw new Error("data key mismatch")
const image = await decryptImage(dataKey, b64(vectors.ciphertext), vectors.image_aad)
if (Buffer.compare(Buffer.from(image), Buffer.from(b64(vectors.image))) !== 0) throw new Error("image mismatch")
let refused = false
await openSealedDataKey(privateKey, b64(vectors.public_key), b64(vectors.sealed_key), `${vectors.handoff_aad}x`).catch(() => { refused = true })
if (!refused) throw new Error("another aad opened the data key")
const pair = await generateHandoffKeyPair()
if (pair.privateKey.extractable) throw new Error("the private key is extractable")
console.log("ok: Node opened the Ruby handoff vector")
