import { createConsumer } from "@rails/actioncable"
import { getCsrfToken } from "utilities/editor_utils"
import { show as notifyShow } from "utilities/notify"

export default class MealPlanSync {
  constructor({ slug, stateUrl, cachePrefix, onStateUpdate, remoteUpdateMessage }) {
    this.stateUrl = stateUrl
    this.onStateUpdate = onStateUpdate
    this.remoteUpdateMessage = remoteUpdateMessage
    this.storageKey = `${cachePrefix}-${slug}`
    this.pendingKey = `${cachePrefix}-pending-${slug}`

    this.version = 0
    this.state = {}
    this.pending = []
    this.awaitingOwnAction = false
    this.initialFetch = true

    this.loadCache()
    this.loadPending()

    if (this.state && Object.keys(this.state).length > 0) {
      this.onStateUpdate(this.state)
    }

    this.fetchState()
    this.subscribe(slug)
    this.startHeartbeat()
    this.flushPending()

    this.boundHandleStreamRender = this.handleStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.boundHandleStreamRender)
  }

  sendAction(url, params, method = "PATCH") {
    this.awaitingOwnAction = true

    return fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": getCsrfToken() || ""
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
        if (!err.status) {
          this.pending.push({ url, params, method })
          this.savePending()
        }
        this.awaitingOwnAction = false
      })
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

  fetchState() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.stateUrl, {
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
          this.onStateUpdate(data)
          if (isRemoteUpdate) {
            notifyShow(this.remoteUpdateMessage)
          }
        }
      })
      .catch(() => {})
  }

  fetchStateWithNotification() {
    if (this.fetchController) this.fetchController.abort()
    this.fetchController = new AbortController()

    fetch(this.stateUrl, {
      headers: { "Accept": "application/json" },
      signal: this.fetchController.signal
    })
      .then(response => {
        if (!response.ok) throw new Error("fetch failed")
        return response.json()
      })
      .then(data => {
        this.version = data.version
        this.state = data
        this.saveCache()
        this.onStateUpdate(data)
        notifyShow(this.remoteUpdateMessage)
      })
      .catch(() => {})
  }

  subscribe(slug) {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "MealPlanChannel", kitchen_slug: slug },
      {
        received: (data) => {
          if (data.type === "content_changed") {
            this.fetchStateWithNotification()
            return
          }
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

  flushPending() {
    if (this.pending.length === 0) return

    const queue = this.pending.slice()
    this.pending = []
    this.savePending()

    queue.forEach(entry => {
      this.sendAction(entry.url, entry.params, entry.method)
    })
  }

  handleStreamRender(event) {
    const originalRender = event.detail.render
    event.detail.render = async (streamElement) => {
      await originalRender(streamElement)
      if (this.state && Object.keys(this.state).length > 0) {
        this.onStateUpdate(this.state)
      }
    }
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
