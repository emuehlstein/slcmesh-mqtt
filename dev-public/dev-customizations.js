// dev-scope.chicagooffline.com customizations
(function () {
  'use strict';

  // --- Replace dark mode button with toggle switch ---
  function replaceDarkToggle() {
    var btn = document.getElementById('darkModeToggle');
    if (!btn || btn.tagName === 'LABEL') return; // already replaced

    var label = document.createElement('label');
    label.className = 'theme-toggle';
    label.id = 'darkModeToggle';
    label.title = 'Toggle dark/light mode';
    label.setAttribute('aria-label', 'Toggle dark mode');
    label.innerHTML =
      '<input type="checkbox" id="darkModeCheckbox" aria-hidden="true">' +
      '<span class="theme-toggle-track">' +
        '<span class="theme-toggle-thumb"></span>' +
        '<span class="theme-toggle-icon theme-toggle-sun">☀️</span>' +
        '<span class="theme-toggle-icon theme-toggle-moon">🌙</span>' +
      '</span>';

    btn.parentNode.replaceChild(label, btn);

    var checkbox = label.querySelector('#darkModeCheckbox');

    // Sync checkbox with current theme
    function syncCheckbox() {
      checkbox.checked = document.documentElement.getAttribute('data-theme') === 'dark';
    }
    new MutationObserver(function (muts) {
      muts.forEach(function (m) { if (m.attributeName === 'data-theme') syncCheckbox(); });
    }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    syncCheckbox();

    // Checkbox drives theme change
    checkbox.addEventListener('change', function () {
      var theme = checkbox.checked ? 'dark' : 'light';
      document.documentElement.setAttribute('data-theme', theme);
      localStorage.setItem('meshcore-theme', theme);
      window.dispatchEvent(new CustomEvent('theme-changed', { detail: { theme: theme } }));
      window.dispatchEvent(new CustomEvent('theme-refresh'));
    });

    // Stop click from bubbling to any stale app.js handler on the old button
    label.addEventListener('click', function (e) { e.stopPropagation(); });
  }

  // --- Remove emojis from nav link text ---
  function cleanNavEmojis() {
    var links = document.querySelectorAll('.nav-links .nav-link, .nav-more-menu .nav-link');
    links.forEach(function (a) {
      // Strip leading emoji + space (e.g. "🔴 Live" → "Live", "⚡ Perf" → "Perf")
      a.textContent = a.textContent.replace(/^[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]\s*/u, '').trim();
    });
  }

  // --- Add emojis to nav stats labels ---
  function patchStatEmojis() {
    var el = document.getElementById('navStats');
    if (!el) return;
    var _busy = false;
    function addEmojis() {
      if (_busy) return;
      var html = el.innerHTML;
      if (html.indexOf('📦') !== -1) return; // already patched
      _busy = true;
      el.innerHTML = html
        .replace(/(<span class="stat-val">[^<]+<\/span>)\s*pkts/g,  '📦 $1 pkts')
        .replace(/(<span class="stat-val">[^<]+<\/span>)\s*nodes/g, '🔵 $1 nodes')
        .replace(/(<span class="stat-val">[^<]+<\/span>)\s*obs/g,   '📡 $1 obs');
      _busy = false;
    }
    new MutationObserver(function () { if (!_busy) addEmojis(); })
      .observe(el, { childList: true, subtree: false });
  }

  // Run after DOM is ready (scripts load in order, so DOMContentLoaded may have already fired)
  function init() {
    replaceDarkToggle();
    cleanNavEmojis();
    patchStatEmojis();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
