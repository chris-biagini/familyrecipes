let container = null
let timer = null

function getContainer() {
  if (!container || !container.isConnected) {
    container = document.createElement('div')
    container.className = 'notify-bar'
    container.hidden = true
    document.body.appendChild(container)
  }
  return container
}

export function dismiss(instant) {
  if (timer) {
    clearTimeout(timer)
    timer = null
  }
  const bar = container
  if (!bar || bar.hidden) return
  if (instant) {
    bar.hidden = true
    bar.classList.remove('notify-visible')
    return
  }
  bar.classList.remove('notify-visible')
  let dismissed = false
  bar.addEventListener('transitionend', function handler() {
    bar.removeEventListener('transitionend', handler)
    if (!dismissed) { dismissed = true; bar.hidden = true }
  })
  setTimeout(() => {
    if (!dismissed) { dismissed = true; bar.hidden = true }
  }, 400)
}

export function show(message, options = {}) {
  dismiss(true)

  const bar = getContainer()
  bar.textContent = ''
  bar.hidden = false

  const msg = document.createElement('span')
  msg.className = 'notify-message'
  msg.textContent = message
  bar.appendChild(msg)

  const actions = document.createElement('span')
  actions.className = 'notify-actions'

  if (options.action) {
    const actionBtn = document.createElement('button')
    actionBtn.type = 'button'
    actionBtn.textContent = options.action.label
    actionBtn.className = 'btn'
    actionBtn.addEventListener('click', () => {
      options.action.callback()
      dismiss()
    })
    actions.appendChild(actionBtn)
  }

  const dismissBtn = document.createElement('button')
  dismissBtn.type = 'button'
  dismissBtn.className = 'notify-dismiss'
  dismissBtn.textContent = '\u00d7'
  dismissBtn.setAttribute('aria-label', 'Dismiss')
  dismissBtn.addEventListener('click', () => dismiss())
  actions.appendChild(dismissBtn)

  if (!options.persistent) {
    timer = setTimeout(() => dismiss(), 5000)
  }

  bar.appendChild(actions)
  bar.offsetHeight
  bar.classList.add('notify-visible')
}
