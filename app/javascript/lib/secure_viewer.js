// The secure viewer for ID images (see docs/KYC.md, "The ID image viewer").
//
// - The image shows only in a canvas in this page. There is no image URL,
//   no <img> and no new tab, so "Save image", "Open image in new tab" and
//   drag do not apply.
// - A watermark is tiled across the image: the viewer's name, the viewer's
//   p_id, the UTC time and the public id of the verification or request.
// - Right-click, drag and select are blocked. A print stylesheet hides the
//   viewer (see app/assets/tailwind/application.css).
// - The image blurs when the page is hidden or the window loses focus, and
//   unblurs on focus.
//
// Nothing here stops a screenshot or a phone camera. The watermark makes a
// copy traceable to the viewer.

// The watermark lines, from the server's values. time is the server's UTC
// time of the view (ISO 8601). Without it, the browser's clock is used.
export function watermarkLines({ name, pId, subjectId, time: issuedAt }, now = new Date()) {
  const at = issuedAt ? new Date(issuedAt) : now
  const time = `${at.toISOString().slice(0, 16).replace("T", " ")} UTC`
  return [`${name} (${pId})`, `${time} · ${subjectId}`]
}

// The positions of the watermark tiles that cover a width x height area,
// for a tile of tileWidth x tileHeight. The rows are offset by half a tile.
export function watermarkTiles(width, height, tileWidth, tileHeight) {
  const tiles = []
  const diagonal = Math.ceil(Math.hypot(width, height))
  for (let row = 0, y = -diagonal; y < diagonal; row += 1, y += tileHeight) {
    const offset = row % 2 === 0 ? 0 : tileWidth / 2
    for (let x = -diagonal - offset; x < diagonal; x += tileWidth) tiles.push([x, y])
  }
  return tiles
}

function drawWatermark(context, width, height, lines) {
  const fontSize = Math.max(14, Math.round(Math.min(width, height) / 28))
  context.save()
  context.font = `600 ${fontSize}px sans-serif`
  const textWidth = Math.max(...lines.map((line) => context.measureText(line).width))
  const tileWidth = textWidth + fontSize * 3
  const tileHeight = fontSize * (lines.length + 3)
  context.translate(width / 2, height / 2)
  context.rotate(-Math.PI / 6)
  context.textBaseline = "top"
  watermarkTiles(width, height, tileWidth, tileHeight).forEach(([x, y]) => {
    lines.forEach((line, index) => {
      const lineY = y + index * fontSize * 1.3
      context.lineWidth = Math.max(2, fontSize / 8)
      context.strokeStyle = "rgba(255, 255, 255, 0.35)"
      context.strokeText(line, x, lineY)
      context.fillStyle = "rgba(42, 32, 80, 0.38)"
      context.fillText(line, x, lineY)
    })
  })
  context.restore()
}

const BLOCKED_EVENTS = ["contextmenu", "dragstart", "selectstart", "copy"]

// Renders the image bytes into a canvas in container. Returns a function
// that clears the canvas and removes the listeners. Throws when the browser
// can't decode this file type (for example a PDF).
export async function renderSecureImage(container, { bytes, contentType, watermark }) {
  const blob = new Blob([bytes], { type: contentType })
  let bitmap
  try {
    bitmap = await createImageBitmap(blob)
  } catch (_error) {
    throw new Error("This browser can't show this file type in the secure viewer.")
  }

  const canvas = document.createElement("canvas")
  canvas.width = bitmap.width
  canvas.height = bitmap.height
  canvas.className = "secure-viewer-canvas"
  canvas.setAttribute("role", "img")
  canvas.setAttribute("aria-label", "The ID image, with a watermark")
  canvas.draggable = false
  const context = canvas.getContext("2d")
  context.drawImage(bitmap, 0, 0)
  bitmap.close?.()
  drawWatermark(context, canvas.width, canvas.height, watermarkLines(watermark))

  const block = (event) => event.preventDefault()
  BLOCKED_EVENTS.forEach((name) => container.addEventListener(name, block))
  const blur = () => container.classList.add("secure-viewer-blurred")
  const sharpen = () => { if (!document.hidden && document.hasFocus()) container.classList.remove("secure-viewer-blurred") }
  const onVisibility = () => (document.hidden ? blur() : sharpen())
  document.addEventListener("visibilitychange", onVisibility)
  window.addEventListener("blur", blur)
  window.addEventListener("focus", sharpen)

  container.classList.add("secure-viewer")
  container.replaceChildren(canvas)

  return () => {
    BLOCKED_EVENTS.forEach((name) => container.removeEventListener(name, block))
    document.removeEventListener("visibilitychange", onVisibility)
    window.removeEventListener("blur", blur)
    window.removeEventListener("focus", sharpen)
    context.clearRect(0, 0, canvas.width, canvas.height)
    canvas.width = 0
    canvas.height = 0
    container.replaceChildren()
  }
}

export function base64ToBytes(value) {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0))
}

// Fetches the image for the viewer: a POST, so the endpoint is never a
// page to open, with no-store so no cache keeps the bytes.
export async function fetchSecureImage(url) {
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "Cache-Control": "no-store, no-cache",
      Pragma: "no-cache",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
    }
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || `The server answered ${response.status}.`)
  return data
}
