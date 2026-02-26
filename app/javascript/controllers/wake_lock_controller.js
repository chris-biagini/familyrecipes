import { Controller } from "@hotwired/stimulus"
import { show as notifyShow, dismiss as notifyDismiss } from "utilities/notify"

export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 600000 },
    warning: { type: Number, default: 480000 }
  }

  connect() {
    if (!('wakeLock' in navigator)) return

    this.lock = null
    this.acquiring = false
    this.inactivityTimer = null
    this.warningTimer = null
    this.warningShown = false

    this.boundOnActivity = this.onActivity.bind(this)
    this.boundOnVisibility = this.onVisibilityChange.bind(this)

    window.addEventListener('scroll', this.boundOnActivity, { passive: true })
    document.addEventListener('pointerdown', this.boundOnActivity)
    document.addEventListener('change', this.boundOnActivity)
    document.addEventListener('visibilitychange', this.boundOnVisibility)

    this.resetTimer()
  }

  disconnect() {
    this.clearTimers()
    this.releaseLock()

    if (this.warningShown) {
      notifyDismiss(true)
      this.warningShown = false
    }

    window.removeEventListener('scroll', this.boundOnActivity)
    document.removeEventListener('pointerdown', this.boundOnActivity)
    document.removeEventListener('change', this.boundOnActivity)
    document.removeEventListener('visibilitychange', this.boundOnVisibility)
  }

  acquire() {
    if (this.lock || this.acquiring) return
    this.acquiring = true
    navigator.wakeLock.request('screen').then(sentinel => {
      this.lock = sentinel
      this.acquiring = false
      this.lock.addEventListener('release', () => { this.lock = null })
    }).catch(() => { this.acquiring = false })
  }

  releaseLock() {
    if (this.lock) {
      this.lock.release().catch(() => {})
      this.lock = null
    }
  }

  clearTimers() {
    if (this.inactivityTimer) { clearTimeout(this.inactivityTimer); this.inactivityTimer = null }
    if (this.warningTimer) { clearTimeout(this.warningTimer); this.warningTimer = null }
  }

  resetTimer() {
    this.clearTimers()
    if (this.warningShown) {
      notifyDismiss(true)
      this.warningShown = false
    }
    if (!this.lock) this.acquire()

    this.warningTimer = setTimeout(() => {
      this.warningShown = true
      notifyShow('Screen will sleep soon \u2014 tap anywhere to stay awake', {
        persistent: true,
        action: { label: 'Stay awake', callback: () => this.resetTimer() }
      })
    }, this.warningValue)

    this.inactivityTimer = setTimeout(() => {
      if (this.warningShown) {
        notifyDismiss(true)
        this.warningShown = false
      }
      this.releaseLock()
    }, this.timeoutValue)
  }

  onActivity() {
    this.resetTimer()
  }

  onVisibilityChange() {
    if (document.visibilityState === 'visible') {
      this.resetTimer()
    } else {
      this.clearTimers()
      if (this.warningShown) {
        notifyDismiss(true)
        this.warningShown = false
      }
      this.releaseLock()
    }
  }
}
