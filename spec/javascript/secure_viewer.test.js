// Checks the pure parts of the secure ID image viewer.
// Run with: bun test spec/javascript
import { describe, expect, test } from "bun:test"
import { base64ToBytes, watermarkLines, watermarkTiles } from "../../app/javascript/lib/secure_viewer"

describe("secure viewer", () => {
  test("puts the viewer, the p_id, the UTC time and the subject id in the watermark", () => {
    const lines = watermarkLines({ name: "Ada Lovelace", pId: "PWL1", subjectId: "verif_abc", time: "2026-10-20T14:05:09Z" })
    expect(lines).toEqual(["Ada Lovelace (PWL1)", "2026-10-20 14:05 UTC · verif_abc"])
  })

  test("uses the browser clock when the server sends no time", () => {
    const lines = watermarkLines({ name: "A", pId: "P", subjectId: "S" }, new Date("2026-01-02T03:04:00Z"))
    expect(lines[1]).toBe("2026-01-02 03:04 UTC · S")
  })

  test("tiles the watermark over the whole rotated area", () => {
    const tiles = watermarkTiles(800, 600, 200, 100)
    const diagonal = Math.ceil(Math.hypot(800, 600))
    expect(tiles.length).toBeGreaterThan(40)
    expect(Math.min(...tiles.map(([x]) => x))).toBeLessThanOrEqual(-diagonal)
    expect(Math.max(...tiles.map(([, y]) => y))).toBeGreaterThanOrEqual(diagonal - 100)
  })

  test("decodes Base64 to bytes", () => {
    expect(Array.from(base64ToBytes("AAEC/w=="))).toEqual([0, 1, 2, 255])
  })
})
