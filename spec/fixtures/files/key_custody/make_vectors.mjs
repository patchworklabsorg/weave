// Makes spec/fixtures/files/key_custody/shamir_vectors.json with the audited
// "shamir-secret-sharing" library that the ceremony page uses:
//
//   bun spec/fixtures/files/key_custody/make_vectors.mjs > spec/fixtures/files/key_custody/shamir_vectors.json
//
// With a JSON array of hex shares as the argument, it combines them instead
// (to check shares that Ruby made).
import { split, combine } from "shamir-secret-sharing";
const hex = (u) => Buffer.from(u).toString("hex");
const out = [];
const secrets = [
  new Uint8Array(32).fill(0),
  Uint8Array.from({ length: 32 }, (_, i) => i),
  Uint8Array.from(Buffer.from("8f4c1a9e2b7d3f6051c8e9a4b2d7f3061e5c9a8b4d2f7e3c6a1b5d9f2e4c8a7b", "hex")),
  new Uint8Array([0xff]),
];
if (process.argv[2]) {
  const shares = JSON.parse(process.argv[2]).map((h) => Uint8Array.from(Buffer.from(h, "hex")));
  console.log(hex(await combine(shares)));
} else {
  for (const s of secrets) {
    const shares = await split(s, 3, 2);
    out.push({ secret: hex(s), threshold: 2, shares: shares.map(hex) });
  }
  const five = Uint8Array.from(Buffer.from("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", "hex"));
  out.push({ secret: hex(five), threshold: 3, shares: (await split(five, 5, 3)).map(hex) });
  console.log(JSON.stringify(out, null, 1));
}
