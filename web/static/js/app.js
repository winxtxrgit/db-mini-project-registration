/* JS เสริมเท่านั้น: ปิด JS แล้วทุกหน้ายังใช้งานได้ครบ (ฟอร์มส่งค่าไปที่ server ตามปกติ) */
(function () {
  "use strict";
  document.documentElement.classList.remove("no-js");

  /* ---------- ธีม: อัตโนมัติ → สว่าง → มืด (เก็บใน localStorage) */
  var THEMES = ["auto", "light", "dark"];
  var THEME_LABEL = { auto: "ธีม: ตามเครื่อง", light: "ธีม: สว่าง", dark: "ธีม: มืด" };
  function currentTheme() { return localStorage.getItem("theme") || "auto"; }
  function applyTheme(t) {
    if (t === "auto") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", t);
    document.querySelectorAll("[data-theme-toggle]").forEach(function (btn) {
      btn.setAttribute("aria-label", THEME_LABEL[t] + " (กดเพื่อเปลี่ยน)");
      btn.setAttribute("title", THEME_LABEL[t]);
      btn.querySelectorAll("[data-theme-icon]").forEach(function (ic) {
        ic.hidden = ic.getAttribute("data-theme-icon") !== t;
      });
    });
  }
  applyTheme(currentTheme());
  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-theme-toggle]");
    if (!btn) return;
    var next = THEMES[(THEMES.indexOf(currentTheme()) + 1) % THEMES.length];
    localStorage.setItem("theme", next);
    applyTheme(next);
  });

  /* ---------- ปิดข้อความแจ้ง */
  document.addEventListener("click", function (e) {
    var btn = e.target.closest(".flash-close");
    if (btn) btn.closest(".flash").remove();
  });

  /* ---------- กันกดส่งซ้ำ: ล็อกปุ่มระหว่างส่งฟอร์ม */
  document.addEventListener("submit", function (e) {
    var btn = e.submitter || e.target.querySelector("button[type=submit], button:not([type])");
    if (!btn || e.defaultPrevented) return;
    setTimeout(function () { btn.setAttribute("aria-busy", "true"); btn.disabled = true; }, 0);
  });
  /* กลับมาด้วยปุ่ม back (bfcache) แล้วปุ่มต้องกดได้อีก */
  window.addEventListener("pageshow", function () {
    document.querySelectorAll("button[aria-busy=true]").forEach(function (b) {
      b.removeAttribute("aria-busy"); b.disabled = false;
    });
  });

  /* ---------- แสดง/ซ่อนรหัสผ่าน */
  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-toggle-password]");
    if (!btn) return;
    var input = document.getElementById(btn.getAttribute("data-toggle-password"));
    var show = input.type === "password";
    input.type = show ? "text" : "password";
    btn.setAttribute("aria-pressed", String(show));
    btn.setAttribute("aria-label", show ? "ซ่อนรหัสผ่าน" : "แสดงรหัสผ่าน");
  });

  /* ---------- ตัวกรองรายการ
     <div data-filter-scope>
       <input data-filter-text>                      ค้นหาจาก data-text ของแต่ละแถว
       <button class="chip" data-filter-chip="key">  แสดงเฉพาะแถวที่ data-tags มี key ("all" = ทั้งหมด)
       <tr data-filter-item data-text="..." data-tags="a b">
       <select data-filter-select>                   แสดงเฉพาะแถวที่ data-tags มีค่าที่เลือก (เว้นว่าง = ทั้งหมด)
       <p data-filter-empty hidden>                 แสดงเมื่อไม่มีแถวตรงเงื่อนไข                       */
  document.querySelectorAll("[data-filter-scope]").forEach(function (scope) {
    var input = scope.querySelector("[data-filter-text]");
    var chips = scope.querySelectorAll("[data-filter-chip]");
    var items = scope.querySelectorAll("[data-filter-item]");
    var selects = scope.querySelectorAll("[data-filter-select]");   /* ค่าที่เลือก = tag ที่ต้องมี ("" = ทั้งหมด) */
    var empty = scope.querySelector("[data-filter-empty]");
    var live = scope.querySelector("[data-filter-status]");
    var active = "all";

    function run() {
      var q = (input ? input.value : "").trim().toLowerCase();
      var shown = 0;
      items.forEach(function (it) {
        var text = (it.getAttribute("data-text") || it.textContent).toLowerCase();
        var tags = " " + (it.getAttribute("data-tags") || "") + " ";
        var ok = (!q || text.indexOf(q) !== -1) && (active === "all" || tags.indexOf(" " + active + " ") !== -1);
        selects.forEach(function (sel) {
          if (sel.value && tags.indexOf(" " + sel.value + " ") === -1) ok = false;
        });
        it.hidden = !ok;
        if (ok) shown++;
      });
      if (empty) empty.hidden = shown !== 0;
      if (live) live.textContent = "แสดง " + shown + " จาก " + items.length + " รายการ";
    }
    if (input) input.addEventListener("input", run);
    selects.forEach(function (sel) { sel.addEventListener("change", run); });
    chips.forEach(function (chip) {
      chip.addEventListener("click", function () {
        active = chip.getAttribute("data-filter-chip");
        chips.forEach(function (c) { c.setAttribute("aria-pressed", String(c === chip)); });
        run();
      });
    });
    run();
  });

  /* ---------- เปิด <details> ที่ตรงกับ #hash (เช่น #sec12) */
  function openHash() {
    if (!location.hash) return;
    var el = document.getElementById(location.hash.slice(1));
    if (el && el.tagName === "DETAILS") el.open = true;
  }
  openHash();
  window.addEventListener("hashchange", openHash);
})();
