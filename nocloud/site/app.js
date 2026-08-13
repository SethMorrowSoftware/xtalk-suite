/* No Cloud Quick Share - landing page progressive enhancement.
 *
 * Everything here is optional polish: the page is fully readable, navigable and
 * styled with JavaScript switched off. No dependencies, no build step, no network
 * calls - it is CSP-clean (default-src 'self') so the same folder can be served
 * from Quick Share itself, over Tor, or opened straight off disk.
 *
 * Six small enhancements: (1) a persisted light/dark theme toggle, (2) a mobile
 * nav drawer, (3) copy-to-clipboard for the clone command, (4) a scroll-spy that
 * lights the current section in the nav, (5) a "scrolled" state on the sticky
 * header, and (6) reveal-on-scroll for the section bands.
 */
(function () {
  "use strict";

  var root = document.documentElement;

  /* ---------------------------------------------------------------- theme toggle */
  // The stylesheet decides light/dark from prefers-color-scheme by default; a manual
  // choice is expressed by stamping data-theme on <html> and remembered in localStorage.
  // (An inline <script> in <head> would avoid the first-paint flash, but that needs a
  // CSP hash; the flash here is one frame and we favour the strict same-origin policy.)
  var THEME_KEY = "ncqs-theme";

  function storedTheme() {
    try { return localStorage.getItem(THEME_KEY); } catch (e) { return null; }
  }
  function saveTheme(v) {
    try { if (v) localStorage.setItem(THEME_KEY, v); else localStorage.removeItem(THEME_KEY); } catch (e) {}
  }
  // What is actually showing right now - the explicit stamp if set, else the OS pref.
  function effectiveTheme() {
    var t = root.getAttribute("data-theme");
    if (t === "light" || t === "dark") return t;
    return (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) ? "dark" : "light";
  }
  function applyTheme(v) {
    if (v === "light" || v === "dark") root.setAttribute("data-theme", v);
    else root.removeAttribute("data-theme");
    var meta = document.querySelector('meta[name="theme-color"]');
    // (the two media-scoped theme-color metas keep the browser UI right when no override;
    //  when overridden we nudge the primary one to match the visible surface)
    var btn = document.getElementById("themebtn");
    if (btn) {
      var now = effectiveTheme();
      btn.setAttribute("aria-label", now === "dark" ? "Switch to light theme" : "Switch to dark theme");
      btn.setAttribute("aria-pressed", now === "dark" ? "true" : "false");
    }
  }

  var saved = storedTheme();
  if (saved === "light" || saved === "dark") applyTheme(saved);
  else applyTheme(null);

  var themeBtn = document.getElementById("themebtn");
  if (themeBtn) {
    themeBtn.addEventListener("click", function () {
      var next = effectiveTheme() === "dark" ? "light" : "dark";
      applyTheme(next);
      saveTheme(next);
    });
  }
  // Follow the OS if the user has not pinned a preference.
  if (window.matchMedia) {
    var mq = window.matchMedia("(prefers-color-scheme: dark)");
    var onMq = function () { if (!storedTheme()) applyTheme(null); };
    if (mq.addEventListener) mq.addEventListener("change", onMq);
    else if (mq.addListener) mq.addListener(onMq);
  }

  /* ---------------------------------------------------------------- mobile nav drawer */
  var navToggle = document.getElementById("navtoggle");
  var topnav = document.querySelector(".topnav");
  if (navToggle && topnav) {
    var setNav = function (open) {
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
      topnav.classList.toggle("open", open);
    };
    navToggle.addEventListener("click", function () {
      setNav(navToggle.getAttribute("aria-expanded") !== "true");
    });
    // Any link tap, or Escape, closes the drawer.
    topnav.addEventListener("click", function (e) {
      if (e.target.closest("a")) setNav(false);
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") setNav(false);
    });
  }

  /* ---------------------------------------------------------------- copy the clone command */
  var copyBtn = document.getElementById("copybtn");
  var cloneCmd = document.getElementById("clonecmd");
  if (copyBtn && cloneCmd) {
    // Only the runnable line, not the trailing "# then open ..." comment.
    var cmdText = function () {
      var lines = cloneCmd.textContent.split("\n");
      for (var i = 0; i < lines.length; i++) {
        var ln = lines[i].trim();
        if (ln && ln.charAt(0) !== "#") return ln;
      }
      return cloneCmd.textContent.trim();
    };
    var flash = function (ok) {
      var was = copyBtn.textContent;
      copyBtn.textContent = ok ? "Copied" : "Copy failed";
      copyBtn.classList.toggle("copied", ok);
      setTimeout(function () { copyBtn.textContent = was; copyBtn.classList.remove("copied"); }, 1600);
    };
    copyBtn.addEventListener("click", function () {
      var text = cmdText();
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { flash(true); }, function () { legacyCopy(text, flash); });
      } else {
        legacyCopy(text, flash);
      }
    });
  }
  function legacyCopy(text, done) {
    try {
      var ta = document.createElement("textarea");
      ta.value = text; ta.setAttribute("readonly", "");
      ta.style.position = "fixed"; ta.style.top = "-1000px";
      document.body.appendChild(ta); ta.select();
      var ok = document.execCommand && document.execCommand("copy");
      document.body.removeChild(ta);
      done(!!ok);
    } catch (e) { done(false); }
  }

  /* ---------------------------------------------------------------- sticky header shadow */
  var chrome = document.getElementById("chrome");
  if (chrome) {
    var onScroll = function () { chrome.classList.toggle("scrolled", window.scrollY > 8); };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* ---------------------------------------------------------------- scroll-spy */
  // Light the nav pill for whichever section owns the viewport. IntersectionObserver
  // keeps it cheap - no scroll-handler math.
  var navLinks = Array.prototype.slice.call(document.querySelectorAll(".topnav a[href^='#']"));
  if (navLinks.length && "IntersectionObserver" in window) {
    var byId = {};
    var sections = [];
    navLinks.forEach(function (a) {
      var id = a.getAttribute("href").slice(1);
      var sec = document.getElementById(id);
      if (sec) { byId[id] = a; sections.push(sec); }
    });
    var current = null;
    var setCurrent = function (id) {
      if (id === current) return;
      current = id;
      navLinks.forEach(function (a) { a.classList.remove("on"); });
      if (id && byId[id]) byId[id].classList.add("on");
    };
    var visible = {};
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { visible[en.target.id] = en.isIntersecting ? en.intersectionRatio : 0; });
      // Pick the section with the greatest visible share.
      var best = null, bestR = 0;
      sections.forEach(function (s) {
        var r = visible[s.id] || 0;
        if (r > bestR) { bestR = r; best = s.id; }
      });
      if (best) setCurrent(best);
    }, { rootMargin: "-45% 0px -45% 0px", threshold: [0, .25, .5, 1] });
    sections.forEach(function (s) { spy.observe(s); });
  }

  /* ---------------------------------------------------------------- reveal-on-scroll */
  var reveals = Array.prototype.slice.call(document.querySelectorAll(".band, .stats, .cta"));
  if (reveals.length && "IntersectionObserver" in window &&
      !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)) {
    reveals.forEach(function (el) { el.classList.add("reveal"); });
    var io = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); obs.unobserve(en.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: .06 });
    reveals.forEach(function (el) { io.observe(el); });
  }
})();
