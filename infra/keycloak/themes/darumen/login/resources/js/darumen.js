/* Darumen · страницы входа Keycloak. Без внешних зависимостей; страницы работают и без JS (обычные поля и ссылки).
   - [data-dm-toggle]      «Показать / Скрыть» пароль
   - [data-dm-strength]    шкала надёжности и чек-лист правил политики (.dm-meter, .dm-rules)
   - [data-dm-confirm]     подсказка «пароли не совпадают»
   - [data-dm-otp="6"]     шесть полей по цифре поверх настоящего поля кода: автопереход, Backspace, вставка
   - [data-dm-countdown]   «Отправить повторно через 0:59» → ссылка
   - [data-dm-if-password] на info-странице: «Пароль изменён», если эта вкладка только что сохранила новый пароль
   - [data-dm-service-status] скрытое предупреждение «Почтовый сервер недоступен»: показывается, только если API сайта
                           (адрес в атрибуте, GET /api/v1/public/service-status) отвечает email.available === false
   - [data-dm-site="путь"] ссылка на сайт («Зарегистрировать организацию»): адрес сайта берётся из redirect_uri запроса входа —
                           его Keycloak уже сверил со списком разрешённых адресов клиента, — поэтому ссылка ведёт туда,
                           откуда человек пришёл (:3000 в Docker, :5173 при npm run dev, стенд), а не на baseUrl из импорта realm */
(function () {
  "use strict";

  function each(sel, fn) { Array.prototype.forEach.call(document.querySelectorAll(sel), fn); }

  // «Показать / Скрыть»
  each("[data-dm-toggle]", function (btn) {
    var input = document.getElementById(btn.getAttribute("data-dm-toggle"));
    if (!input) return;
    btn.addEventListener("click", function () {
      var show = input.type === "password";
      input.type = show ? "text" : "password";
      btn.textContent = show ? btn.dataset.hide : btn.dataset.show;
      btn.setAttribute("aria-pressed", String(show));
      input.focus();
    });
  });

  // Надёжность нового пароля: правила из политики realm (data-* у .dm-rules)
  each("[data-dm-strength]", function (input) {
    var rules = document.querySelector(".dm-rules");
    var meter = document.querySelector(".dm-meter");
    if (!rules || !meter) return;
    var label = meter.querySelector(".dm-meter-label");
    var labels = (label.dataset.labels || "").split("|");
    var min = parseInt(rules.dataset.min, 10) || 12;
    var needUpper = parseInt(rules.dataset.upper, 10) || 0;
    var needLower = parseInt(rules.dataset.lower, 10) || 0;
    var needDigits = parseInt(rules.dataset.digits, 10) || 0;
    var user = (rules.dataset.user || "").toLowerCase();

    function count(value, re) { return (value.match(re) || []).length; }
    function checks(value) {
      return {
        length: value.length >= min,
        "case": count(value, /\p{Lu}/gu) >= Math.max(needUpper, 1) && count(value, /\p{Ll}/gu) >= Math.max(needLower, 1),
        digit: count(value, /\d/g) >= Math.max(needDigits, 1),
        user: !user || value.toLowerCase() !== user
      };
    }
    function update() {
      var value = input.value;
      var result = checks(value);
      var items = rules.querySelectorAll("li[data-rule]");
      var passed = 0;
      Array.prototype.forEach.call(items, function (li) {
        var ok = value.length > 0 && result[li.dataset.rule];
        li.classList.toggle("ok", !!ok);
        if (ok) passed++;
      });
      var level = 0;
      if (value.length > 0) {
        if (!result.length) level = 1;
        else if (passed < items.length) level = 2;
        else level = (value.length >= min + 4 || /[^\p{L}\d]/u.test(value)) ? 4 : 3;
      }
      meter.dataset.level = String(level);
      label.textContent = labels[level] || "";
    }
    input.addEventListener("input", update);
    update();
  });

  // Повтор пароля
  each("[data-dm-confirm]", function (confirm) {
    var source = document.getElementById(confirm.dataset.dmConfirm);
    var hint = document.getElementById("input-error-" + confirm.id);
    if (!source || !hint) return;
    var serverText = hint.textContent.trim();
    function update() {
      var mismatch = confirm.value.length > 0 && source.value.length > 0 && confirm.value !== source.value &&
        !source.value.startsWith(confirm.value);
      if (mismatch) {
        hint.textContent = confirm.dataset.mismatch;
        hint.hidden = false;
        confirm.setAttribute("aria-invalid", "true");
      } else if (!serverText || confirm.value.length > 0) {
        hint.hidden = true;
        confirm.setAttribute("aria-invalid", "false");
      }
    }
    confirm.addEventListener("input", update);
    source.addEventListener("input", update);
  });

  // Код из приложения-аутентификатора: N полей по цифре поверх настоящего input
  each("[data-dm-otp]", function (real) {
    var n = parseInt(real.dataset.dmOtp, 10) || 6;
    var digitLabel = real.dataset.digitLabel || "";
    var wrap = document.createElement("div");
    wrap.className = "dm-otp";
    wrap.setAttribute("role", "group");
    if (real.labels && real.labels[0]) {
      real.labels[0].id = real.labels[0].id || real.id + "-label";
      wrap.setAttribute("aria-labelledby", real.labels[0].id);
      real.labels[0].htmlFor = real.id + "-1";
    }
    if (real.getAttribute("aria-invalid") === "true") wrap.setAttribute("aria-invalid", "true");
    var boxes = [];
    for (var i = 0; i < n; i++) {
      var box = document.createElement("input");
      box.type = "text";
      box.inputMode = "numeric";
      box.maxLength = 1;
      box.autocomplete = i === 0 ? "one-time-code" : "off";
      box.id = real.id + "-" + (i + 1);
      box.setAttribute("aria-label", digitLabel.replace("{0}", String(i + 1)));
      box.dataset.index = String(i);
      boxes.push(box);
      wrap.appendChild(box);
    }
    real.type = "hidden";
    real.removeAttribute("autofocus");
    real.parentNode.insertBefore(wrap, real);

    function sync() {
      real.value = boxes.map(function (b) { return b.value; }).join("");
      if (real.value.length === n) {
        var submit = real.form && real.form.querySelector("button[type=submit]:not([name=cancel-aia])");
        if (submit) submit.focus();
      }
    }
    function fill(from, digits) {
      for (var k = 0; k < digits.length && from + k < n; k++) boxes[from + k].value = digits[k];
      var next = Math.min(from + digits.length, n - 1);
      boxes[next].focus();
      sync();
    }
    boxes.forEach(function (box, idx) {
      box.addEventListener("input", function () {
        var digits = box.value.replace(/\D/g, "");
        box.value = "";
        if (digits) fill(idx, digits.split("")); else sync();
      });
      box.addEventListener("keydown", function (e) {
        if (e.key === "Backspace" && !box.value && idx > 0) { boxes[idx - 1].value = ""; boxes[idx - 1].focus(); sync(); e.preventDefault(); }
        else if (e.key === "ArrowLeft" && idx > 0) { boxes[idx - 1].focus(); e.preventDefault(); }
        else if (e.key === "ArrowRight" && idx < n - 1) { boxes[idx + 1].focus(); e.preventDefault(); }
      });
      box.addEventListener("paste", function (e) {
        var text = (e.clipboardData || window.clipboardData).getData("text") || "";
        var digits = text.replace(/\D/g, "").slice(0, n);
        if (!digits) return;
        e.preventDefault();
        fill(digits.length === n ? 0 : idx, digits.split(""));
      });
      box.addEventListener("focus", function () { box.select(); });
    });
    boxes[0].focus();
  });

  // «Пароль изменён»: метка ставится при отправке формы нового пароля и снимается при каждом показе этой формы
  var PWD_KEY = "dmPasswordSaved";
  function store(fn) { try { return fn(window.sessionStorage); } catch (e) { return null; } }
  each("[data-dm-password-form]", function (form) {
    store(function (s) { s.removeItem(PWD_KEY); });
    form.addEventListener("submit", function () { store(function (s) { s.setItem(PWD_KEY, String(Date.now())); }); });
  });
  var savedAt = +(store(function (s) { return s.getItem(PWD_KEY); }) || 0);
  if (document.querySelector("[data-dm-if-password]")) {
    if (savedAt && Date.now() - savedAt < 10 * 60 * 1000) {
      each("[data-dm-if-password]", function (el) { el.textContent = el.getAttribute("data-dm-if-password"); });
      each("[data-dm-show-if-password]", function (el) { el.hidden = false; });
      document.title = document.querySelector("h1").textContent.trim() + " · Darumen Health";
    }
    store(function (s) { s.removeItem(PWD_KEY); });
  }

  // Почта недоступна: предупреждение скрыто по умолчанию и открывается по ответу API. Нет ответа за 5 с, ошибка или
  // чужой формат — статус неизвестен, предупреждение не показываем. Без cookies: статус публичный.
  each("[data-dm-service-status]", function (note) {
    if (!window.fetch) return;
    var controller = window.AbortController ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, 5000) : 0;
    fetch(note.getAttribute("data-dm-service-status"), {
      headers: { Accept: "application/json" },
      credentials: "omit",
      signal: controller ? controller.signal : undefined
    })
      .then(function (response) { return response.ok ? response.json() : null; })
      .then(function (status) {
        if (status && status.email && status.email.available === false) note.hidden = false;
      })
      .catch(function () { /* статус неизвестен */ })
      .then(function () { clearTimeout(timer); });
  });

  // Ссылки на сайт — на тот адрес, с которого начат вход
  (function () {
    var key = "darumen.site";
    var site = null;
    try {
      var redirect = new URLSearchParams(window.location.search).get("redirect_uri");
      if (redirect && /^https?:/i.test(redirect)) {
        site = new URL(redirect).origin + "/";
        window.sessionStorage.setItem(key, site);
      } else {
        site = window.sessionStorage.getItem(key);
      }
    } catch (e) { site = null; }
    if (!site) return;
    each("[data-dm-site]", function (link) {
      link.setAttribute("href", site + (link.getAttribute("data-dm-site") || ""));
    });
  })();

  // Повторная отправка письма — после паузы
  each("[data-dm-countdown]", function (link) {
    var left = parseInt(link.dataset.dmCountdown, 10) || 60;
    var href = link.getAttribute("href");
    function fmt(s) { return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    function tick() {
      if (left <= 0) {
        link.setAttribute("href", href);
        link.removeAttribute("aria-disabled");
        link.textContent = link.dataset.label;
        return;
      }
      link.textContent = (link.dataset.wait || "").replace("{0}", fmt(left));
      left--;
      setTimeout(tick, 1000);
    }
    link.removeAttribute("href");
    link.setAttribute("aria-disabled", "true");
    tick();
  });
})();
