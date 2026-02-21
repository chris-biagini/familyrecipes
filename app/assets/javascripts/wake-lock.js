(function() {
  if (!('wakeLock' in navigator)) return;

  var TIMEOUT = 10 * 60 * 1000;     // 10 minutes
  var WARNING = 8 * 60 * 1000;      // warn at 8 minutes (2 min before expiry)
  var lock = null;
  var acquiring = false;
  var inactivityTimer = null;
  var warningTimer = null;
  var warningShown = false;

  function acquire() {
    if (lock || acquiring) return;
    acquiring = true;
    navigator.wakeLock.request('screen').then(function(sentinel) {
      lock = sentinel;
      acquiring = false;
      lock.addEventListener('release', function() { lock = null; });
    }).catch(function() { acquiring = false; });
  }

  function release() {
    if (lock) {
      lock.release().catch(function() {});
      lock = null;
    }
  }

  function clearTimers() {
    if (inactivityTimer) { clearTimeout(inactivityTimer); inactivityTimer = null; }
    if (warningTimer) { clearTimeout(warningTimer); warningTimer = null; }
  }

  function resetTimer() {
    clearTimers();
    if (warningShown) {
      Notify.dismiss(true);
      warningShown = false;
    }
    if (!lock) acquire();

    warningTimer = setTimeout(function() {
      warningShown = true;
      Notify.show('Screen will sleep soon \u2014 tap anywhere to stay awake', {
        persistent: true,
        action: { label: 'Stay awake', callback: function() { resetTimer(); } }
      });
    }, WARNING);

    inactivityTimer = setTimeout(function() {
      if (warningShown) {
        Notify.dismiss(true);
        warningShown = false;
      }
      release();
    }, TIMEOUT);
  }

  function onActivity() {
    resetTimer();
  }

  function onVisibilityChange() {
    if (document.visibilityState === 'visible') {
      resetTimer();
    } else {
      clearTimers();
      if (warningShown) {
        Notify.dismiss(true);
        warningShown = false;
      }
      release();
    }
  }

  // Listen for user activity
  window.addEventListener('scroll', onActivity, { passive: true });
  document.addEventListener('pointerdown', onActivity);
  document.addEventListener('change', onActivity);

  document.addEventListener('visibilitychange', onVisibilityChange);

  // Start on load
  resetTimer();
})();
