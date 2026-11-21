(function (factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else api.mount(document, window);
})(function () {
  const packageName = 'com.rdtech.carrodasdelicias';
  function productIdFromPath(path) {
    const match = /^\/produto\/([1-9]\d*)\/?$/.exec(path);
    return match ? match[1] : null;
  }
  function linksFor(id) {
    const store = 'https://play.google.com/store/apps/details?id=' + packageName +
      (id ? '&referrer=' + encodeURIComponent('produto=' + id) : '');
    return {store, app: 'carrodasdelicias://produto/' + id,
      intent: 'intent://produto/' + id + '#Intent;scheme=carrodasdelicias;package=' + packageName +
        ';S.browser_fallback_url=' + encodeURIComponent(store) + ';end'};
  }
  function mount(doc, win) {
    const id = productIdFromPath(win.location.pathname);
    const links = linksFor(id);
    const appButton = doc.getElementById('open-app');
    const storeButton = doc.getElementById('open-store');
    const android = /Android/i.test(win.navigator.userAgent);
    let fallback;
    storeButton.href = links.store;
    if (!id) {
      doc.getElementById('message').textContent = 'O link do produto não é válido. Você pode encontrar o catálogo no aplicativo.';
      appButton.hidden = true;
      return;
    }
    appButton.href = android ? links.intent : links.app;
    const open = function () {
      win.clearTimeout(fallback);
      win.location.href = android ? links.intent : links.app;
      fallback = win.setTimeout(function () {
        if (!doc.hidden) win.location.replace(links.store);
      }, 1800);
    };
    appButton.addEventListener('click', function (event) { event.preventDefault(); open(); });
    doc.addEventListener('visibilitychange', function () { if (doc.hidden) win.clearTimeout(fallback); });
    win.addEventListener('pagehide', function () { win.clearTimeout(fallback); });
    if (android) win.setTimeout(open, 100);
  }
  return {productIdFromPath, linksFor, mount};
});
