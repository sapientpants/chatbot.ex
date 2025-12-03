// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/chatbot"
import topbar from "../vendor/topbar"

// Lazy-load highlight.js for code blocks (reduces initial bundle size)
let hljsPromise = null

async function loadHighlightJs() {
  if (hljsPromise) return hljsPromise

  hljsPromise = (async () => {
    const [
      {default: hljs},
      {default: elixir},
      {default: javascript},
      {default: python},
      {default: bash},
      {default: json},
      {default: sql},
      {default: css},
      {default: xml}
    ] = await Promise.all([
      import("highlight.js/lib/core"),
      import("highlight.js/lib/languages/elixir"),
      import("highlight.js/lib/languages/javascript"),
      import("highlight.js/lib/languages/python"),
      import("highlight.js/lib/languages/bash"),
      import("highlight.js/lib/languages/json"),
      import("highlight.js/lib/languages/sql"),
      import("highlight.js/lib/languages/css"),
      import("highlight.js/lib/languages/xml")
    ])

    // Register languages
    hljs.registerLanguage("elixir", elixir)
    hljs.registerLanguage("javascript", javascript)
    hljs.registerLanguage("js", javascript)
    hljs.registerLanguage("python", python)
    hljs.registerLanguage("bash", bash)
    hljs.registerLanguage("shell", bash)
    hljs.registerLanguage("json", json)
    hljs.registerLanguage("sql", sql)
    hljs.registerLanguage("css", css)
    hljs.registerLanguage("html", xml)
    hljs.registerLanguage("xml", xml)

    window.hljs = hljs
    return hljs
  })()

  return hljsPromise
}

// Custom hooks
const Hooks = {
  ...colocatedHooks,

  // Auto-grow textarea as user types and handle Enter/Shift+Enter
  AutoGrowTextarea: {
    MAX_HEIGHT: 200,
    mounted() {
      this.el.addEventListener("input", () => this.resize())
      this.el.addEventListener("keydown", (e) => this.handleKeydown(e))
      this.resize()
      // Focus the textarea on mount
      this.el.focus()
    },
    updated() {
      // Reset height after form clears (don't auto-focus to avoid stealing focus)
      this.resize()
    },
    resize() {
      this.el.style.height = "auto"
      this.el.style.height = Math.min(this.el.scrollHeight, this.MAX_HEIGHT) + "px"
    },
    handleKeydown(e) {
      // Enter without Shift submits the form
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        const form = this.el.closest("form")
        if (form && this.el.value.trim()) {
          form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }))
        }
      }
      // Shift+Enter adds a newline (default behavior, no need to handle)
    }
  },

  // Citation highlighter - makes superscript footnote references clickable
  CitationHighlighter: {
    // Superscript character mappings
    SUPERSCRIPTS: {
      "¹": 1, "²": 2, "³": 3, "⁴": 4, "⁵": 5, "⁶": 6, "⁷": 7, "⁸": 8, "⁹": 9,
      "¹⁰": 10, "¹¹": 11, "¹²": 12, "¹³": 13, "¹⁴": 14, "¹⁵": 15,
      "¹⁶": 16, "¹⁷": 17, "¹⁸": 18, "¹⁹": 19, "²⁰": 20
    },

    mounted() {
      this.sources = JSON.parse(this.el.dataset.ragSources || "[]")
      this.highlightCitations()
      this.setupModal()
    },

    updated() {
      this.sources = JSON.parse(this.el.dataset.ragSources || "[]")
      this.highlightCitations()
    },

    setupModal() {
      // Create modal if it doesn't exist
      if (!document.getElementById("citation-modal")) {
        const modal = document.createElement("dialog")
        modal.id = "citation-modal"
        modal.className = "modal"
        modal.innerHTML = `
          <div class="modal-box max-w-2xl">
            <form method="dialog">
              <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">✕</button>
            </form>
            <h3 class="font-bold text-lg mb-2" id="citation-modal-title">Source</h3>
            <div class="text-sm text-base-content/60 mb-3" id="citation-modal-meta"></div>
            <div class="prose prose-sm max-w-full" id="citation-modal-content"></div>
          </div>
          <form method="dialog" class="modal-backdrop">
            <button>close</button>
          </form>
        `
        document.body.appendChild(modal)
      }
    },

    // Convert number to superscript string
    toSuperscript(num) {
      const superscripts = {
        1: "¹", 2: "²", 3: "³", 4: "⁴", 5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹",
        10: "¹⁰", 11: "¹¹", 12: "¹²", 13: "¹³", 14: "¹⁴", 15: "¹⁵",
        16: "¹⁶", 17: "¹⁷", 18: "¹⁸", 19: "¹⁹", 20: "²⁰"
      }
      return superscripts[num] || `[${num}]`
    },

    highlightCitations() {
      if (this.sources.length === 0) return

      // Create a regex that matches all superscript patterns (two-digit first, then single)
      const superscriptPattern = /¹⁰|¹¹|¹²|¹³|¹⁴|¹⁵|¹⁶|¹⁷|¹⁸|¹⁹|²⁰|[¹²³⁴⁵⁶⁷⁸⁹]/g

      // Find the References section header if it exists
      const referencesHeader = this.findReferencesHeader()

      // First pass: collect all citations in order of appearance to build renumbering map
      // Only process citations BEFORE the References section
      const walker1 = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null, false)
      const citationOrder = [] // Original indices in order of first appearance
      let node1
      while ((node1 = walker1.nextNode())) {
        // Stop when we reach the References section
        if (referencesHeader && this.isInOrAfterReferences(node1, referencesHeader)) {
          break
        }
        superscriptPattern.lastIndex = 0
        let match
        while ((match = superscriptPattern.exec(node1.textContent)) !== null) {
          const originalIndex = this.SUPERSCRIPTS[match[0]]
          if (originalIndex && !citationOrder.includes(originalIndex)) {
            citationOrder.push(originalIndex)
          }
        }
      }

      // Build mapping: original index -> new sequential index (starting from 1)
      const renumberMap = {}
      citationOrder.forEach((originalIndex, i) => {
        renumberMap[originalIndex] = i + 1
      })

      // Build renumbered sources for the modal
      this.renumberedSources = {}
      citationOrder.forEach((originalIndex, i) => {
        const source = this.sources.find(s => (s.index || s["index"]) === originalIndex)
        if (source) {
          this.renumberedSources[i + 1] = {
            ...source,
            displayIndex: i + 1
          }
        }
      })

      // Reorder and renumber the References section if it exists
      if (referencesHeader) {
        this.reorderReferencesSection(referencesHeader, renumberMap)
      }

      // Second pass: replace citations with renumbered clickable links (outside References)
      const walker2 = document.createTreeWalker(this.el, NodeFilter.SHOW_TEXT, null, false)
      const nodesToProcess = []
      let node2
      while ((node2 = walker2.nextNode())) {
        // Skip nodes in/after the References section (already handled)
        if (referencesHeader && this.isInOrAfterReferences(node2, referencesHeader)) {
          continue
        }
        superscriptPattern.lastIndex = 0
        if (superscriptPattern.test(node2.textContent)) {
          nodesToProcess.push(node2)
        }
        superscriptPattern.lastIndex = 0
      }

      nodesToProcess.forEach(textNode => {
        const text = textNode.textContent
        const fragment = document.createDocumentFragment()
        let lastIndex = 0
        let match

        superscriptPattern.lastIndex = 0
        while ((match = superscriptPattern.exec(text)) !== null) {
          const originalIndex = this.SUPERSCRIPTS[match[0]]
          const newIndex = renumberMap[originalIndex]
          const source = this.renumberedSources[newIndex]

          // Add text before the match
          if (match.index > lastIndex) {
            fragment.appendChild(document.createTextNode(text.slice(lastIndex, match.index)))
          }

          if (source) {
            // Create clickable span with renumbered citation
            const span = document.createElement("span")
            span.textContent = this.toSuperscript(newIndex)
            span.className = "citation-link cursor-pointer text-primary hover:underline font-semibold"
            span.dataset.sourceIndex = newIndex
            const filename = source.filename || source["filename"]
            span.title = `Click to view source: ${filename}`
            span.addEventListener("click", (e) => {
              e.preventDefault()
              e.stopPropagation()
              this.showSource(source, newIndex)
            })
            fragment.appendChild(span)
          } else {
            // No source found, just add the original text
            fragment.appendChild(document.createTextNode(match[0]))
          }

          lastIndex = match.index + match[0].length
        }

        // Add remaining text
        if (lastIndex < text.length) {
          fragment.appendChild(document.createTextNode(text.slice(lastIndex)))
        }

        // Replace the text node
        textNode.parentNode.replaceChild(fragment, textNode)
      })
    },

    // Find the References heading element
    findReferencesHeader() {
      // Look for h2 with "References" text
      const headings = this.el.querySelectorAll("h2, h3, strong")
      for (const heading of headings) {
        if (heading.textContent.trim().toLowerCase() === "references") {
          return heading
        }
      }
      return null
    },

    // Check if a node is in or after the References section
    isInOrAfterReferences(node, referencesHeader) {
      // Compare document position
      const position = referencesHeader.compareDocumentPosition(node)
      // Node is after or contained by referencesHeader's parent
      return (position & Node.DOCUMENT_POSITION_FOLLOWING) !== 0 ||
             (position & Node.DOCUMENT_POSITION_CONTAINED_BY) !== 0
    },

    // Reorder and renumber the References section
    reorderReferencesSection(referencesHeader, renumberMap) {
      const superscriptPattern = /¹⁰|¹¹|¹²|¹³|¹⁴|¹⁵|¹⁶|¹⁷|¹⁸|¹⁹|²⁰|[¹²³⁴⁵⁶⁷⁸⁹]/g

      // Find the container for reference items (usually following siblings or parent's children)
      const container = referencesHeader.parentElement
      if (!container) return

      // Collect reference lines: look for elements that start with a superscript
      const referenceItems = []
      let sibling = referencesHeader.nextElementSibling || referencesHeader.parentElement.nextElementSibling

      // Also check if references are in a list or paragraphs after the heading
      const possibleContainers = container.parentElement ?
        Array.from(container.parentElement.children).filter(el => {
          const position = referencesHeader.compareDocumentPosition(el)
          return (position & Node.DOCUMENT_POSITION_FOLLOWING) !== 0
        }) : []

      // Try to find reference items in various formats
      for (const el of [sibling, ...possibleContainers]) {
        if (!el) continue

        // Check if this element contains a superscript at the start
        const text = el.textContent
        superscriptPattern.lastIndex = 0
        const match = superscriptPattern.exec(text)

        if (match && match.index < 3) { // Superscript near the start
          const originalIndex = this.SUPERSCRIPTS[match[0]]
          const newIndex = renumberMap[originalIndex]
          if (newIndex) {
            referenceItems.push({
              element: el,
              originalIndex,
              newIndex,
              html: el.innerHTML
            })
          }
        }
      }

      // Sort by new index and renumber
      referenceItems.sort((a, b) => a.newIndex - b.newIndex)

      // Update each reference item with the correct number
      referenceItems.forEach(item => {
        const newSuperscript = this.toSuperscript(item.newIndex)
        const source = this.renumberedSources[item.newIndex]

        // Replace the old superscript with the new one and make it clickable
        const walker = document.createTreeWalker(item.element, NodeFilter.SHOW_TEXT, null, false)
        let textNode
        let processed = false

        while ((textNode = walker.nextNode()) && !processed) {
          superscriptPattern.lastIndex = 0
          const match = superscriptPattern.exec(textNode.textContent)

          if (match) {
            const text = textNode.textContent
            const fragment = document.createDocumentFragment()

            // Text before superscript
            if (match.index > 0) {
              fragment.appendChild(document.createTextNode(text.slice(0, match.index)))
            }

            // Create clickable superscript
            if (source) {
              const span = document.createElement("span")
              span.textContent = newSuperscript
              span.className = "citation-link cursor-pointer text-primary hover:underline font-semibold"
              span.dataset.sourceIndex = item.newIndex
              const filename = source.filename || source["filename"]
              span.title = `Click to view source: ${filename}`
              span.addEventListener("click", (e) => {
                e.preventDefault()
                e.stopPropagation()
                this.showSource(source, item.newIndex)
              })
              fragment.appendChild(span)
            } else {
              fragment.appendChild(document.createTextNode(newSuperscript))
            }

            // Text after superscript
            fragment.appendChild(document.createTextNode(text.slice(match.index + match[0].length)))

            textNode.parentNode.replaceChild(fragment, textNode)
            processed = true
          }
        }
      })

      // Reorder DOM elements if needed
      if (referenceItems.length > 1) {
        const parent = referenceItems[0].element.parentElement
        if (parent) {
          // Sort elements by their new index
          referenceItems.forEach(item => {
            parent.appendChild(item.element)
          })
        }
      }
    },

    showSource(source, displayIndex) {
      const modal = document.getElementById("citation-modal")
      const title = document.getElementById("citation-modal-title")
      const meta = document.getElementById("citation-modal-meta")
      const content = document.getElementById("citation-modal-content")

      // Use display index for the title (renumbered)
      const idx = displayIndex || source.displayIndex || source.index || source["index"]
      const filename = source.filename || source["filename"]
      const section = source.section || source["section"]
      const sourceContent = source.content || source["content"]

      title.textContent = `Source ${idx}: ${filename}`
      meta.textContent = section ? `Section: ${section}` : ""

      // Render content as plain text with line breaks
      content.innerHTML = this.escapeHtml(sourceContent)
        .replace(/\n/g, "<br>")

      modal.showModal()
    },

    escapeHtml(text) {
      const div = document.createElement("div")
      div.textContent = text
      return div.innerHTML
    }
  },

  // Scroll to bottom when new messages arrive and highlight code
  // Uses flex-col-reverse so scrollTop=0 shows the bottom (no flicker on load)
  ScrollToBottom: {
    mounted() {
      this.highlightCode().catch(err => console.error("Failed to highlight code:", err))
    },
    updated() {
      this.highlightCode().catch(err => console.error("Failed to highlight code:", err))
      this.scrollToBottom()
    },
    scrollToBottom() {
      // With flex-col-reverse, scrollTop=0 is the bottom
      this.el.scrollTop = 0
    },
    async highlightCode() {
      // Only load highlight.js if there are code blocks to highlight
      const unhighlightedBlocks = this.el.querySelectorAll("pre code:not(.hljs)")
      if (unhighlightedBlocks.length === 0) return

      // Lazy-load highlight.js on first use
      const hljs = await loadHighlightJs()
      unhighlightedBlocks.forEach((block) => {
        hljs.highlightElement(block)
      })
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

// Handle download events
window.addEventListener("phx:download", (event) => {
  const {filename, content} = event.detail
  const blob = new Blob([content], {type: "text/plain"})
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#f97316"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
