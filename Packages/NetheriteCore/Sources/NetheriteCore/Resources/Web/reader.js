(function () {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
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
      target.classList.add('flash');
    }
  };
  document.addEventListener('change', e => {
    if (e.target.classList.contains('task-checkbox')) post({ type: 'task', line: parseInt(e.target.dataset.line, 10) });
  });
  document.addEventListener('DOMContentLoaded', () => {
    renderMath(); highlight(); renderMermaid();
    if (window.netheriteInitialSubpath) window.netheriteScrollTo(window.netheriteInitialSubpath);
  });
})();
