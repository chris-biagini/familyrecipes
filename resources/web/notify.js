var Notify = (function() {
  var container = null;
  var timer = null;

  function getContainer() {
    if (!container) {
      container = document.createElement('div');
      container.className = 'notify-bar';
      container.hidden = true;
      document.body.appendChild(container);
    }
    return container;
  }

  function dismiss(instant) {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    var bar = container;
    if (!bar || bar.hidden) return;
    if (instant) {
      bar.hidden = true;
      bar.classList.remove('notify-visible');
      return;
    }
    bar.classList.remove('notify-visible');
    var dismissed = false;
    bar.addEventListener('transitionend', function handler() {
      bar.removeEventListener('transitionend', handler);
      if (!dismissed) { dismissed = true; bar.hidden = true; }
    });
    setTimeout(function() {
      if (!dismissed) { dismissed = true; bar.hidden = true; }
    }, 400);
  }

  function show(message, options) {
    options = options || {};
    dismiss(true);

    var bar = getContainer();
    bar.innerHTML = '';
    bar.hidden = false;

    var msg = document.createElement('span');
    msg.className = 'notify-message';
    msg.textContent = message;
    bar.appendChild(msg);

    var actions = document.createElement('span');
    actions.className = 'notify-actions';

    if (options.action) {
      var actionBtn = document.createElement('button');
      actionBtn.type = 'button';
      actionBtn.textContent = options.action.label;
      actionBtn.className = 'notify-btn notify-btn-action';
      actionBtn.addEventListener('click', function() {
        options.action.callback();
        dismiss();
      });
      actions.appendChild(actionBtn);
    }

    var dismissBtn = document.createElement('button');
    dismissBtn.type = 'button';
    dismissBtn.className = 'notify-dismiss';
    dismissBtn.textContent = '\u00d7';
    dismissBtn.setAttribute('aria-label', 'Dismiss');
    dismissBtn.addEventListener('click', function() {
      dismiss();
    });
    actions.appendChild(dismissBtn);

    if (!options.persistent) {
      timer = setTimeout(function() {
        dismiss();
      }, 5000);
    }

    bar.appendChild(actions);

    // Trigger slide-in animation
    bar.offsetHeight;
    bar.classList.add('notify-visible');
  }

  return { show: show, dismiss: dismiss };
})();
