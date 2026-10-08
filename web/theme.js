/* Тема панели: «авто» (как в системе), «день» или «ночь». Выбор хранится в этом браузере.
   Подключается в <head>, чтобы страница сразу открывалась в нужной теме, без вспышки. */
(function(){
  var KEY = 'fsr-theme', root = document.documentElement, ORDER = ['auto', 'light', 'dark'];
  var LABEL = {auto: ['◐', 'Тема: как в системе'], light: ['☀', 'Тема: дневная'], dark: ['☾', 'Тема: ночная']};
  function get(){ try { var v = localStorage.getItem(KEY); return ORDER.indexOf(v) > 0 ? v : 'auto'; } catch(e){ return 'auto'; } }
  function isLight(mode){ return mode === 'light' || (mode === 'auto' && window.matchMedia && matchMedia('(prefers-color-scheme: light)').matches); }
  function apply(mode){
    if(mode === 'auto') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', mode);
    var meta = document.querySelector('meta[name="theme-color"]');
    if(meta) meta.setAttribute('content', isLight(mode) ? '#e9efe0' : '#050605');
    var b = document.getElementById('theme-btn');
    if(b){ b.textContent = LABEL[mode][0]; b.title = LABEL[mode][1] + ' — нажми, чтобы сменить'; b.setAttribute('aria-label', LABEL[mode][1]); }
  }
  apply(get());
  if(window.matchMedia) matchMedia('(prefers-color-scheme: light)').addEventListener('change', function(){ apply(get()); });
  document.addEventListener('DOMContentLoaded', function(){
    var b = document.getElementById('theme-btn'); if(!b) return;
    apply(get());
    b.addEventListener('click', function(){
      var next = ORDER[(ORDER.indexOf(get()) + 1) % ORDER.length];
      try { if(next === 'auto') localStorage.removeItem(KEY); else localStorage.setItem(KEY, next); } catch(e){}
      apply(next);
    });
  });
})();
