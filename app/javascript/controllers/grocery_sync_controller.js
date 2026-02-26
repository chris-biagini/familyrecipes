import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { show as notifyShow } from "utilities/notify"

export default class extends Controller {
  connect() {
    const slug = this.element.dataset.kitchenSlug

    this.storageKey = `grocery-state-${slug}`
    this.pendingKey = `grocery-pending-${slug}`
    this.version = 0
    this.state = {}
    this.pending = []
    this.awaitingOwnAction = false
    this.initialFetch = true

    this.urls = {
      state: this.element.dataset.stateUrl,
      select: this.element.dataset.selectUrl,
      check: this.element.dataset.checkUrl,
      customItems: this.element.dataset.customItemsUrl,
      clear: this.element.dataset.clearUrl
    }

    this.loadCache()
    this.loadPending()

    if (this.state && Object.keys(this.state).length > 0) {
      this.applyStateToUI(this.state)
    }

    this.initialFetch = true
    this.fetchState()
    this.subscribe(slug)
    this.startHeartbeat()
    this.flushPending()

    this.boundHandleStreamRender = this.handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
  }

  disconnect() {
    if (this.fetchController) this.fetchController.abort()
    if (this.heartbeatId) {
      clearInterval(this.heartbeatId)
      this.heartbeatId = null
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
    if (this.boundHandleStreamRender) {
      document.removeEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
    }
  }

  get uiController() {
    return this.application.getControllerForElementAndIdentifier(this.element, "grocery-ui")
  }

  applyStateToUI(state) {
    const ui = this.uiController
    if (ui) ui.applyState(state)
  }

  handleStreamRender(event) {
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      if (this.state && Object.keys(this.state).length > 0) {
        this.applyStateToUI(this.state)
      }
    }
  }

  fetchState() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.urls.state, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        if (data.version >= this.version) {
          const isRemoteUpdate = data.version > this.version
            && this.version > 0
            && !this.awaitingOwnAction
            && !this.initialFetch
          this.awaitingOwnAction = false
          this.initialFetch = false
          this.version = data.version
          this.state = data
          this.saveCache()
          this.applyStateToUI(data)
          if (isRemoteUpdate) {
            notifyShow("List updated from another device.")
          }
        }
      })
      .catch(() => {})
  }

  sendAction(url, params) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')
    const method = url === this.urls.clear ? "DELETE" : "PATCH"

    this.awaitingOwnAction = true

    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken ? csrfToken.content : ""
      },
      body: JSON.stringify(params)
    })
      .then(response => {
        if (!response.ok) {
          const err = new Error("action failed")
          err.status = response.status
          throw err
        }
        return response.json()
      })
      .then(() => {
        this.fetchState()
      })
      .catch(err => {
        this.awaitingOwnAction = false
        if (!err.status) {
          this.pending.push({ url, params })
          this.savePending()
        }
      })
  }

  flushPending() {
    if (this.pending.length === 0) return

    const queue = this.pending.slice()
    this.pending = []
    this.savePending()

    queue.forEach(entry => {
      this.sendAction(entry.url, entry.params)
    })
  }

  subscribe(slug) {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "GroceryListChannel", kitchen_slug: slug },
      {
        received: (data) => {
          if (data.version && data.version > this.version && !this.awaitingOwnAction) {
            this.fetchState()
          }
        },
        connected: () => {
          this.flushPending()
        }
      }
    )
  }

  startHeartbeat() {
    this.heartbeatId = setInterval(() => this.fetchState(), 30000)
  }

  saveCache() {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify({
        version: this.version,
        state: this.state
      }))
    } catch { /* localStorage full or unavailable */ }
  }

  loadCache() {
    try {
      const raw = localStorage.getItem(this.storageKey)
      if (!raw) return
      const cached = JSON.parse(raw)
      if (cached && cached.version) {
        this.version = cached.version
        this.state = cached.state || {}
      }
    } catch { /* corrupted cache */ }
  }

  savePending() {
    try {
      if (this.pending.length > 0) {
        localStorage.setItem(this.pendingKey, JSON.stringify(this.pending))
      } else {
        localStorage.removeItem(this.pendingKey)
      }
    } catch { /* localStorage full or unavailable */ }
  }

  loadPending() {
    try {
      const raw = localStorage.getItem(this.pendingKey)
      if (raw) {
        this.pending = JSON.parse(raw) || []
      }
    } catch {
      this.pending = []
    }
  }
}
