// 홈페이지 움직임만 맡는다: 스크롤 등장 · 머리줄 그림자 · 폰 기울기.
// 이 파일이 없거나 막혀도 내용은 다 보인다(styles.css 가 .js 가 있을 때만 숨긴다).
document.documentElement.classList.add('js');

document.addEventListener('DOMContentLoaded', function () {
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // 화면에 들어온 것만 나타나게 한다. 한 번 나타나면 더 지켜보지 않는다.
  var items = document.querySelectorAll('.reveal');
  if (still || !('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('in'); });
  } else {
    var seen = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('in');
        seen.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    items.forEach(function (el) { seen.observe(el); });
  }

  var header = document.querySelector('.site-header');
  var onScroll = function () { header.classList.toggle('is-scrolled', window.scrollY > 8); };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // 마우스가 있는 기기에서만 폰이 마우스 쪽으로 살짝 기운다.
  var hero = document.querySelector('.hero');
  var tilt = document.querySelector('.phone-tilt');
  if (!hero || !tilt || still || !window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;
  hero.addEventListener('pointermove', function (e) {
    var box = hero.getBoundingClientRect();
    var x = (e.clientX - box.left) / box.width - 0.5;
    var y = (e.clientY - box.top) / box.height - 0.5;
    tilt.style.setProperty('--ry', (x * 14).toFixed(2) + 'deg');
    tilt.style.setProperty('--rx', (-y * 10).toFixed(2) + 'deg');
  });
  hero.addEventListener('pointerleave', function () {
    tilt.style.removeProperty('--ry');
    tilt.style.removeProperty('--rx');
  });
});
