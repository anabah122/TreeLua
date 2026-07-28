// RU/EN toggle: every page holds two parallel blocks, <div lang="en"> and
// <div lang="ru">, inside main. This just flips which one is visible and
// remembers the choice — no reload, no per-string wiring.
function applyLang(lang) {
  document.documentElement.setAttribute("data-lang", lang);
  localStorage.setItem("treelua-docs-lang", lang);
  document.querySelectorAll(".lang-toggle button").forEach(btn => {
    btn.classList.toggle("active", btn.dataset.lang === lang);
  });
}

function initLang() {
  const saved = localStorage.getItem("treelua-docs-lang") || "en";
  applyLang(saved);
}

initLang();
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".lang-toggle button").forEach(btn => {
    btn.addEventListener("click", () => applyLang(btn.dataset.lang));
  });
});
