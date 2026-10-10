/* Тема панели: «как в системе», «светлая» или «тёмная». Выбор хранится в этом браузере (localStorage, ключ fsr-theme).
   Подключается в <head>, чтобы страница сразу открывалась в нужной теме, без вспышки. Меню — кнопка #theme-btn в шапке. */
(function(){
  var KEY = 'fsr-theme', root = document.documentElement, MODES = ['auto', 'light', 'dark'];
  var LABEL = {auto: ['sun-moon', 'Тема: как в системе'], light: ['sun', 'Тема: светлая'], dark: ['moon', 'Тема: тёмная']};
  function get(){ try { var v = localStorage.getItem(KEY); return MODES.indexOf(v) > 0 ? v : 'auto'; } catch(e){ return 'auto'; } }
  function isLight(mode){ return mode === 'light' || (mode === 'auto' && window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches); }
  function apply(mode){
    if(mode === 'auto') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', mode);
    var meta = document.querySelector('meta[name="theme-color"]');
    if(meta) meta.setAttribute('content', isLight(mode) ? '#F6F8FB' : '#090B0F');
    var b = document.getElementById('theme-btn');
    if(b){ var u = b.querySelector('use'); if(u) u.setAttribute('href', 'icons.svg#' + LABEL[mode][0]); b.title = LABEL[mode][1]; b.setAttribute('aria-label', LABEL[mode][1]); }
    var items = document.querySelectorAll('[data-theme-set]');
    for(var i = 0; i < items.length; i++) items[i].setAttribute('aria-checked', items[i].getAttribute('data-theme-set') === mode);
  }
  apply(get());
  if(window.matchMedia) matchMedia('(prefers-color-scheme: light)').addEventListener('change', function(){ apply(get()); });
  document.addEventListener('DOMContentLoaded', function(){
    var b = document.getElementById('theme-btn'), m = document.getElementById('theme-menu'); if(!b || !m) return;
    apply(get());
    function open(on, focus){
      m.hidden = !on; b.setAttribute('aria-expanded', on);
      if(on && focus){ var c = m.querySelector('[aria-checked="true"]') || m.querySelector('button'); c.focus(); }
    }
    b.addEventListener('click', function(e){ e.stopPropagation(); open(m.hidden, true); });
    m.addEventListener('click', function(e){
      var t = e.target.closest('[data-theme-set]'); if(!t) return;
      var mode = t.getAttribute('data-theme-set');
      try { if(mode === 'auto') localStorage.removeItem(KEY); else localStorage.setItem(KEY, mode); } catch(err){}
      apply(mode); open(false); b.focus();
    });
    m.addEventListener('keydown', function(e){
      var items = Array.prototype.slice.call(m.querySelectorAll('button')), i = items.indexOf(document.activeElement);
      if(e.key === 'ArrowDown' || e.key === 'ArrowUp'){ e.preventDefault(); items[(i + (e.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length].focus(); }
      if(e.key === 'Escape'){ open(false); b.focus(); }
      if(e.key === 'Tab') open(false);
    });
    document.addEventListener('click', function(e){ if(!m.hidden && !e.target.closest('.tm')) open(false); });
  });
})();
