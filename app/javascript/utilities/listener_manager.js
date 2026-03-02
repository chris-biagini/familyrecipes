/**
 * Tracks DOM event listeners for clean teardown. Stimulus controllers that add
 * listeners to dynamically-selected nodes use this to guarantee removal on
 * disconnect — preventing leaks when Turbo replaces page content.
 *
 * Usage:
 *   this.listeners = new ListenerManager()
 *   this.listeners.add(node, "click", handler)
 *   this.listeners.teardown()
 */
export default class ListenerManager {
  constructor() {
    this.entries = new Map()
  }

  add(node, event, handler) {
    node.addEventListener(event, handler)
    if (!this.entries.has(node)) this.entries.set(node, [])
    this.entries.get(node).push([event, handler])
  }

  teardown() {
    for (const [node, handlers] of this.entries) {
      for (const [event, handler] of handlers) {
        node.removeEventListener(event, handler)
      }
    }
    this.entries.clear()
  }
}
