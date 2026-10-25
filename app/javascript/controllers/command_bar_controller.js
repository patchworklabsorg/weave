import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The ⌘K command bar (shared/_command_bar). The static commands are in the
// DOM already, one .cmdk-item each, grouped under .cmdk-section headers.
// Typing filters them. For admins, it also asks the search URL for users,
// groups and apps and appends those as items built from the <template>s.
//
// This is the Patchwork standard pattern; see internal-docs design/components.md.
export default class extends Controller {
  static targets = ["dialog", "input", "list", "static", "results", "empty", "signout"]
  static values = { searchUrl: String, minLength: { type: Number, default: 2 } }

  connect() {
    this.selected = -1
    this.recent = this.loadRecent()
  }

  // Global listeners (registered as window actions in the partial)
  keydown(event) {
    const key = event.key.toLowerCase()
    if ((event.metaKey || event.ctrlKey) && key === "k") {
      event.preventDefault()
      this.toggle()
    }
  }

  trigger(event) {
    if (event.target.closest("[data-command-bar-trigger]")) this.open()
  }

  toggle() {
    this.dialogTarget.open ? this.close() : this.open()
  }

  open() {
    if (this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  // Clicking the backdrop closes the dialog; clicks inside stay.
  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // Keys inside the input
  navigate(event) {
    const items = this.visibleItems()
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.select(Math.min(this.selected + 1, items.length - 1), items)
        break
      case "ArrowUp":
        event.preventDefault()
        this.select(Math.max(this.selected - 1, 0), items)
        break
      case "Enter":
        event.preventDefault()
        if (items[this.selected]) this.run(items[this.selected])
        break
      case "Escape":
        this.close()
        break
    }
  }

  input() {
    this.filter()
    this.search()
  }

  choose(event) {
    this.run(event.currentTarget)
  }

  hover(event) {
    const items = this.visibleItems()
    this.select(items.indexOf(event.currentTarget), items, { scroll: false })
  }

  // ── Filtering the static commands ──────────────────────────────

  filter() {
    const query = this.query
    const terms = query.split(/\s+/).filter(Boolean)
    let shown = 0

    this.staticTarget.querySelectorAll(".cmdk-section").forEach((section) => {
      let any = false
      section.querySelectorAll(".cmdk-item").forEach((item) => {
        const haystack = `${item.textContent} ${item.dataset.keywords || ""}`.toLowerCase()
        const match = terms.every((term) => haystack.includes(term))
        item.hidden = !match
        if (match) { any = true; shown += 1 }
      })
      section.hidden = !any
    })

    this.renderRecent(query === "")
    this.emptyTarget.hidden = shown > 0 || this.resultsTarget.childElementCount > 0
    this.select(0, this.visibleItems())
  }

  renderRecent(show) {
    const section = this.staticTarget.querySelector("[data-recent]")
    if (!section) return
    section.innerHTML = ""
    const items = show ? this.recent.map((href) => this.staticTarget.querySelector(`.cmdk-item[data-href="${CSS.escape(href)}"]`)).filter(Boolean) : []
    section.hidden = items.length === 0
    if (items.length === 0) return
    const title = document.createElement("div")
    title.className = "cmdk-section-title"
    title.textContent = "Recent"
    section.append(title, ...items.map((item) => {
      const clone = item.cloneNode(true)
      clone.removeAttribute("id") // select() gives the clone its own id
      return clone
    }))

  }

  // ── Server search (admins) ─────────────────────────────────────

  search() {
    clearTimeout(this.timer)
    this.abort?.abort()
    const query = this.query
    if (!this.hasSearchUrlValue || query.length < this.minLengthValue) {
      this.resultsTarget.innerHTML = ""
      this.emptyTarget.hidden = this.visibleItems().length > 0
      return
    }
    this.timer = setTimeout(() => this.fetchResults(query), 180)
  }

  async fetchResults(query) {
    this.abort = new AbortController()
    try {
      const url = new URL(this.searchUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: this.abort.signal
      })
      if (!response.ok) return
      const results = await response.json()
      if (this.query !== query) return
      this.renderResults(results)
    } catch (error) {
      if (error.name !== "AbortError") console.error("command bar search failed", error)
    }
  }

  renderResults(results) {
    this.resultsTarget.innerHTML = ""
    const groups = new Map()
    results.forEach((result) => {
      if (!groups.has(result.type)) groups.set(result.type, [])
      groups.get(result.type).push(result)
    })
    groups.forEach((items, type) => {
      const template = this.element.querySelector(`template[data-result-type="${type}"]`)
      if (!template) return
      const section = document.createElement("div")
      section.className = "cmdk-section"
      const title = document.createElement("div")
      title.className = "cmdk-section-title"
      title.textContent = template.dataset.resultTitle || type
      section.append(title)
      items.forEach((result) => {
        const item = template.content.firstElementChild.cloneNode(true)
        item.dataset.href = result.path
        item.querySelector("[data-label]").textContent = result.label
        const hint = item.querySelector("[data-hint]")
        if (hint) hint.textContent = result.hint || ""
        section.append(item)
      })
      this.resultsTarget.append(section)
    })
    this.emptyTarget.hidden = this.visibleItems().length > 0
    this.select(0, this.visibleItems())
  }

  // ── Selection and running ──────────────────────────────────────

  visibleItems() {
    return Array.from(this.listTarget.querySelectorAll(".cmdk-item")).filter((item) => {
      return !item.hidden && !item.closest("[hidden]")
    })
  }

  // The input is the combobox; aria-activedescendant tells assistive tech
  // which option the arrow keys are on. Options get an id the first time
  // they are selected.
  select(index, items, { scroll = true } = {}) {
    this.selected = items.length === 0 ? -1 : index
    this.inputTarget.removeAttribute("aria-activedescendant")
    items.forEach((item, i) => {
      const on = i === this.selected
      item.setAttribute("aria-selected", String(on))
      if (!on) return
      if (!item.id) item.id = `command_bar_option_${(this.optionCount = (this.optionCount || 0) + 1)}`
      this.inputTarget.setAttribute("aria-activedescendant", item.id)
      if (scroll) item.scrollIntoView({ block: "nearest" })
    })
  }


  run(item) {
    const { href, command } = item.dataset
    this.close()
    if (command === "theme") {
      document.querySelector("[data-theme-toggle]")?.click()
    } else if (command === "signout") {
      this.signoutTarget.requestSubmit()
    } else if (href) {
      this.remember(href)
      Turbo.visit(href)
    }
  }

  get query() {
    return this.inputTarget.value.trim().toLowerCase()
  }

  // Recent picks live in this browser only.
  loadRecent() {
    try { return JSON.parse(localStorage.getItem("weave:command-bar:recent") || "[]") } catch { return [] }
  }

  remember(href) {
    this.recent = [href, ...this.recent.filter((h) => h !== href)].slice(0, 5)
    try { localStorage.setItem("weave:command-bar:recent", JSON.stringify(this.recent)) } catch { /* private window */ }
  }
}
