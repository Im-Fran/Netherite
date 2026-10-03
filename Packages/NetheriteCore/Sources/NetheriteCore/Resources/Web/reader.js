(function () {
  function post(msg) {
    if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.netherite) webkit.messageHandlers.netherite.postMessage(msg);
  }
  function renderMath() {
    if (!window.katex) return;
    document.querySelectorAll('.math[data-tex]').forEach(el => {
      try { katex.render(el.dataset.tex, el, { displayMode: el.classList.contains('math-display'), throwOnError: false }); }
      catch (e) { el.textContent = el.dataset.tex; }
    });
  }
  function renderMermaid() {
    if (!window.mermaid || !document.querySelector('pre.mermaid')) return;
    // A theme can force light or dark through color-scheme; otherwise follow the system.
    const scheme = getComputedStyle(document.documentElement).colorScheme;
    const dark = scheme === 'dark' || (scheme !== 'light' && matchMedia('(prefers-color-scheme: dark)').matches);
    mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
    mermaid.run({ querySelector: 'pre.mermaid' });
  }
  function highlight() {
    if (!window.hljs) return;
    document.querySelectorAll('pre code:not(.nohighlight)').forEach(el => hljs.highlightElement(el));
  }
  window.netheriteScrollTo = function (sub) {
    let el = null;
    if (sub.startsWith('^')) el = document.getElementById(sub);
    else {
      const want = sub.split('#').pop().trim().toLowerCase();
      el = [...document.querySelectorAll('[data-heading]')].find(h => h.dataset.heading.toLowerCase() === want);
    }
    if (el) {
      const target = el.classList.contains('block-id') ? el.parentElement : el;
      target.scrollIntoView({ block: 'start' });
      // Restart the highlight on repeat jumps, and clear it so a Reduce Motion outline doesn't linger.
      target.classList.remove('flash'); void target.offsetWidth; target.classList.add('flash');
      setTimeout(() => target.classList.remove('flash'), 1200);
    }
  };
  let hoverTimer = null;
  document.addEventListener('mouseover', e => {
    const a = e.target.closest && e.target.closest('a.internal-link');
    if (!a) return;
    clearTimeout(hoverTimer);
    hoverTimer = setTimeout(() => {
      const r = a.getBoundingClientRect();
      post({ type: 'hover', href: a.getAttribute('href'), x: r.left, y: r.top, w: r.width, h: r.height });
    }, 600);
  });
  document.addEventListener('mouseout', e => {
    const a = e.target.closest && e.target.closest('a.internal-link');
    if (a) { clearTimeout(hoverTimer); }
  });
  document.addEventListener('change', e => {
    if (e.target.classList.contains('task-checkbox')) post({ type: 'task', line: parseInt(e.target.dataset.line, 10) });
  });
  document.addEventListener('DOMContentLoaded', () => {
    renderMath(); highlight(); renderMermaid();
    if (window.netheriteInitialSubpath) window.netheriteScrollTo(window.netheriteInitialSubpath);
  });
})();
