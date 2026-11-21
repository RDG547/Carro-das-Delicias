const {test} = require('node:test');
const assert = require('node:assert/strict');
const {productIdFromPath, linksFor, mount} = require('../website/abrir-produto.js');
test('aceita apenas caminhos com produto válido', () => {
  assert.equal(productIdFromPath('/produto/67/'), '67');
  for (const path of ['/produto/0','/produto/abc','/produto/1/extra','/outro/1']) assert.equal(productIdFromPath(path), null);
});
test('intent tem pacote correto e fallback Play Store com referência ao produto', () => {
  const links = linksFor('67');
  assert.equal(links.app, 'carrodasdelicias://produto/67');
  assert.match(links.intent, /package=com\.rdtech\.carrodasdelicias;/);
  assert.ok(links.intent.includes(encodeURIComponent(links.store)));
  assert.equal(new URL(links.store).searchParams.get('referrer'), 'produto=67');
});
test('sem app aberto, encaminha à loja; com app aberto, cancela fallback', () => {
  const nodes = Object.fromEntries(['open-app','open-store','message'].map(id => [id,{addEventListener(){}}]));
  const events = {}, timers = new Map(); let sequence = 0, redirected;
  const document = {hidden:false,getElementById:id=>nodes[id],addEventListener:(event,fn)=>events[event]=fn};
  const window = {navigator:{userAgent:'Android Chrome'}, location:{pathname:'/produto/67',replace:url=>redirected=url},
    setTimeout:fn=>{timers.set(++sequence,fn);return sequence},clearTimeout:id=>timers.delete(id),addEventListener(){}};
  mount(document, window); timers.get(1)(); timers.get(2)();
  assert.equal(redirected, linksFor('67').store);
  redirected = undefined; timers.clear(); sequence = 0;
  mount(document,window);timers.get(1)();document.hidden=true;events.visibilitychange();
  assert.equal(timers.has(2),false);assert.equal(redirected,undefined);
});
