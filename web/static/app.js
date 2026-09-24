/* Instalador web NLinux — lógica do assistente + SSE. */
"use strict";

const $ = (s) => document.querySelector(s);
const es = [];
document.querySelectorAll("section.screen").forEach((n) => es.push(n));

function show(id) {
  es.forEach((n) => n.classList.toggle("active", n.id === id));
}

/* ---------- i18n ---------- */
let TR = {};
let UI_LANG = "pt";

const LANG_FROM_LOCALE = {
  "pt_BR.UTF-8": "pt", "pt_PT.UTF-8": "pt",
  "en_US.UTF-8": "en", "en_GB.UTF-8": "en",
  "es_ES.UTF-8": "es", "fr_FR.UTF-8": "fr",
  "de_DE.UTF-8": "de", "it_IT.UTF-8": "it",
  "ja_JP.UTF-8": "ja",
};

async function loadI18n(lang) {
  if (lang && TR === undefined) return;
  lang = lang || "pt";
  try {
    const r = await fetch("/api/i18n?lang=" + encodeURIComponent(lang));
    const d = await r.json();
    TR = d.table || {};
    UI_LANG = d.lang || lang;
  } catch (e) {
    UI_LANG = lang;
  }
}

function t(key) {
  const v = TR[key];
  return v === undefined ? key : v;
}

/* ---------- estado ---------- */
const state = {
  INSTALL_DISK: "",
  FS_TYPE: "",
  LOCALE: "",
  KEYMAP: "",
  ZONEINFO: "",
  MIRROR: "",
  MIRROR_PICKED: false,
  OFFLINE: "",
  USE_LUKS: "",
  LUKS_PASS: "",
  GPU: "",
  HOSTNAME: "nlinux",
  INSTALL_USER: "nlinux",
  INSTALL_USER_PASS: "",
  ROOT_SAME: true,
  ROOT_PASS: "",
  NLLANG: "pt",
};

const LOCALES = [
  { flag: "🇧🇷", name: "Brasil", locale: "pt_BR.UTF-8", keymap: "br-abnt2", zone: "America/Sao_Paulo" },
  { flag: "🇺🇸", name: "Estados Unidos", locale: "en_US.UTF-8", keymap: "us", zone: "America/New_York" },
  { flag: "🇵🇹", name: "Portugal", locale: "pt_PT.UTF-8", keymap: "pt-latin1", zone: "Europe/Lisbon" },
  { flag: "🇬🇧", name: "Reino Unido", locale: "en_GB.UTF-8", keymap: "uk", zone: "Europe/London" },
  { flag: "🇪🇸", name: "Espanha", locale: "es_ES.UTF-8", keymap: "es", zone: "Europe/Madrid" },
  { flag: "🇫🇷", name: "França", locale: "fr_FR.UTF-8", keymap: "fr", zone: "Europe/Paris" },
  { flag: "🇩🇪", name: "Alemanha", locale: "de_DE.UTF-8", keymap: "de", zone: "Europe/Berlin" },
  { flag: "🇮🇹", name: "Itália", locale: "it_IT.UTF-8", keymap: "it", zone: "Europe/Rome" },
  { flag: "🇯🇵", name: "Japão", locale: "ja_JP.UTF-8", keymap: "jp", zone: "Asia/Tokyo" },
];

const MIRRORS = [
  { flag: "🌐", name: "Automático (recomendado)", value: "" },
  { flag: "🇧🇷", name: "Brasil — UFSCar", value: "https://mirror.ufscar.br/archlinux" },
  { flag: "🇺🇸", name: "Estados Unidos — Leaseweb", value: "https://mirror.us.leaseweb.net/archlinux" },
  { flag: "🇩🇪", name: "Alemanha — Dogado", value: "https://mirror.dogado.de/archlinux" },
  { flag: "🇯🇵", name: "Japão — Kyoto", value: "https://mirrors.cat.net/archlinux" },
];

const GPUS = [
  { value: "auto", k: "web.gpu.auto", d: "web.gpu.auto.d" },
  { value: "amd", k: "web.gpu.amd", d: "web.gpu.amd.d" },
  { value: "nvidia", k: "web.gpu.nvidia", d: "web.gpu.nvidia.d" },
  { value: "intel", k: "web.gpu.intel", d: "web.gpu.intel.d" },
];
const GPU_NAME = {};
GPUS.forEach((g) => (GPU_NAME[g.value] = g.k));

/* ---------- infraestrutura do wizard ---------- */
let idx = 0;
const steps = [];

function hideMsg() {
  const m = $("#step-msg");
  if (m) m.hidden = true;
}

function cardGrid(options, pick, extra) {
  const wrap = document.createElement("div");
  wrap.className = "grid";
  options.forEach((o, i) => {
    const c = document.createElement("div");
    c.className = "card";
    c.innerHTML =
      `<div class="check">✓</div>` +
      (o.flag ? `<span class="flag">${o.flag}</span>` : "") +
      `<div><div class="title">${o.name}</div>` +
      (o.desc ? `<div class="desc">${o.desc}</div>` : "") +
      `</div>`;
    c.addEventListener("click", () => {
      hideMsg();
      wrap.querySelectorAll(".card").forEach((x) => x.classList.remove("selected"));
      c.classList.add("selected");
      pick(o);
      (extra || (() => {}))(o, i);
    });
    wrap.appendChild(c);
  });
  return wrap;
}

function h(fields) {
  const wrap = document.createElement("div");
  wrap.className = "field";
  fields.forEach((f) => {
    const box = document.createElement("div");
    box.className = "input";
    const lab = document.createElement("label");
    lab.textContent = t(f.label);
    const inp = document.createElement("input");
    inp.type = f.type || "text";
    inp.value = f.value || "";
    if (f.placeholder) inp.placeholder = t(f.placeholder);
    inp.addEventListener("input", () => {
      hideMsg();
      f.oninput(inp.value);
    });
    box.append(lab, inp);
    wrap.appendChild(box);
  });
  return wrap;
}

function render() {
  const el = $("#step");
  el.innerHTML = "";
  steps[idx].render(el);
  $("#stepper-fill").style.width = `${(idx / (steps.length - 1)) * 100}%`;
  $("#stepper-label").textContent = t(steps[idx].label);
  $("#btn-back").textContent = t("web.back");
  $("#btn-back").style.visibility = idx === 0 ? "hidden" : "visible";
  $("#btn-next").textContent = idx === steps.length - 1 ? t("web.install") : t("web.next");
}

/* ---------- telas ---------- */
const WELCOMES = [
  "Bem-vindo ao instalador do NLinux",
  "Welcome to the NLinux installer",
  "Bienvenido al instalador de NLinux",
  "Bienvenue à l'installateur NLinux",
  "Willkommen beim NLinux-Installer",
  "Benvenuto nell'installatore NLinux",
  "NLinuxインストーラーへようこそ",
];
let welcomeIdx = 0;
setInterval(() => {
  const el = document.getElementById("welcome-anim");
  if (!el) return;
  el.classList.add("hide");
  setTimeout(() => {
    welcomeIdx = (welcomeIdx + 1) % WELCOMES.length;
    el.textContent = WELCOMES[welcomeIdx];
    el.classList.remove("hide");
  }, 320);
}, 2600);

function diskStep() {
  return {
    label: "web.step.disk",
    async render(el) {
      el.innerHTML = `<h2>${t("web.step.disk")}</h2><p class="sub">${t("web.sub.disk")}</p>`;
      const grid = document.createElement("div");
      grid.className = "grid";
      el.appendChild(grid);
      try {
        const r = await fetch("/api/disks");
        const data = await r.json();
        const disks = data.disks || [];
        if (!disks.length) {
          grid.innerHTML = `<div class="warn-box">${t("web.disk.none")}</div>`;
          return;
        }
        disks.forEach((d) => {
          const c = document.createElement("div");
          c.className = "card";
          c.innerHTML =
            `<div class="check">✓</div>` +
            `<div><div class="title">${d.name}</div>` +
            `<div class="desc">${d.size} — ${d.model || "disk"}${d.name === state.INSTALL_DISK ? "" : ""}</div></div>`;
          if (d.name === state.INSTALL_DISK) c.classList.add("selected");
          c.addEventListener("click", () => {
            grid.querySelectorAll(".card").forEach((x) => x.classList.remove("selected"));
            c.classList.add("selected");
            state.INSTALL_DISK = d.name;
          });
          grid.appendChild(c);
        });
      } catch (e) {
        grid.innerHTML = `<div class="warn-box">${t("web.disk.err")}</div>`;
      }
    },
    valid: () => !!state.INSTALL_DISK,
  };
}

function fsStep() {
  return {
    label: "web.step.fs",
    render(el) {
      const options = [
        { name: "ext4", desc: t("fs.ext4d"), value: "ext4", sel: () => state.FS_TYPE === "ext4" },
        { name: "btrfs", desc: t("fs.btrfsd"), value: "btrfs", sel: () => state.FS_TYPE === "btrfs" },
      ];
      el.innerHTML = `<h2>${t("web.step.fs")}</h2><p class="sub">${t("web.sub.fs")}</p>`;
      const g = cardGrid(options, (o) => (state.FS_TYPE = o.value));
      options.forEach((o, i) => o.sel() && g.children[i].classList.add("selected"));
      el.appendChild(g);
    },
    valid: () => !!state.FS_TYPE,
  };
}

function localeStep() {
  return {
    label: "web.step.locale",
    render(el) {
      el.innerHTML =
        `<div class="welcome-hero">` +
        `<h1 id="welcome-anim" class="welcome-anim">${WELCOMES[0]}</h1>` +
        `<div class="brand"><div class="logo-ring">` +
        `<span class="pulse"></span><span class="pulse delay-1"></span>` +
        `<div class="logo-circle"><img src="/static/logo.png" alt="NLinux"></div>` +
        `</div></div>` +
        `</div>`;
      const g = cardGrid(LOCALES, (o) => {
        state.LOCALE = o.locale;
        state.KEYMAP = o.keymap;
        state.ZONEINFO = o.zone;
        state.NLLANG = LANG_FROM_LOCALE[o.locale] || "pt";
        loadI18n(state.NLLANG);
      });
      el.appendChild(g);
    },
    valid: () => !!state.LOCALE,
  };
}

function keymapStep() {
  const options = [
    { flag: "🇧🇷", name: "br-abnt2", value: "br-abnt2" },
    { flag: "🇺🇸", name: "us", value: "us" },
    { flag: "🇵🇹", name: "pt-latin1", value: "pt-latin1" },
    { flag: "🇬🇧", name: "uk", value: "uk" },
    { flag: "🇪🇸", name: "es", value: "es" },
    { flag: "🇫🇷", name: "fr", value: "fr" },
    { flag: "🇩🇪", name: "de", value: "de" },
    { flag: "🇮🇹", name: "it", value: "it" },
    { flag: "🇯🇵", name: "jp", value: "jp" },
  ];
  return {
    label: "web.step.keymap",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.keymap")}</h2><p class="sub">${t("web.sub.keymap")}</p>`;
      const g = cardGrid(options, (o) => (state.KEYMAP = o.value));
      el.appendChild(g);
    },
    valid: () => !!state.KEYMAP,
  };
}

function mirrorStep() {
  return {
    label: "web.step.mirror",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.mirror")}</h2><p class="sub">${t("web.sub.mirror")}</p>`;
      const g = cardGrid(MIRRORS, (o) => {
        state.MIRROR = o.value;
        state.MIRROR_PICKED = true;
      });
      el.appendChild(g);
    },
    valid: () => state.MIRROR_PICKED === true,
  };
}

function typeStep() {
  return {
    label: "web.step.type",
    render(el) {
      const options = [
        { name: t("type.offline"), desc: t("type.offline.sub"), value: "1", sel: () => state.OFFLINE === "1" },
        { name: t("type.online"), desc: t("type.online.sub"), value: "0", sel: () => state.OFFLINE === "0" },
      ];
      el.innerHTML = `<h2>${t("web.step.type")}</h2><p class="sub">${t("web.sub.type")}</p>`;
      const g = cardGrid(options, (o) => (state.OFFLINE = o.value));
      options.forEach((o, i) => o.sel() && g.children[i].classList.add("selected"));
      el.appendChild(g);
    },
    valid: () => state.OFFLINE === "0" || state.OFFLINE === "1",
  };
}

function luksStep() {
  return {
    label: "web.step.luks",
    render(el) {
      const options = [
        { name: t("web.luks.no"), desc: "", value: "0", sel: () => state.USE_LUKS === "0" },
        { name: t("web.luks.luks2"), desc: t("web.luks2.sub"), value: "1", sel: () => state.USE_LUKS === "1" },
      ];
      el.innerHTML = `<h2>${t("web.step.luks")}</h2>`;
      const g = cardGrid(options, (o) => (state.USE_LUKS = o.value));
      el.appendChild(g);
      const box = document.createElement("div");
      box.id = "luks-box";
      el.appendChild(box);
      const sync = (v) => {
        box.innerHTML = "";
        if (v === "1") {
          box.appendChild(
            h([
              { label: "web.luks.pass", type: "password", value: state.LUKS_PASS, oninput: (v) => (state.LUKS_PASS = v) },
              {
                label: "web.luks.confirm",
                type: "password",
                oninput: (v) => (state._luk_conf = v),
              },
            ])
          );
        }
      };
      sync(state.USE_LUKS);
      g.addEventListener("click", (e) => {
        const c = e.target.closest(".card");
        if (c) sync(state.USE_LUKS);
      });
    },
    valid: () =>
      state.USE_LUKS === "0" ||
      (state.USE_LUKS === "1" && state.LUKS_PASS.length > 0 && state.LUKS_PASS === state._luk_conf),
  };
}

function gpuStep() {
  return {
    label: "web.step.gpu",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.gpu")}</h2><p class="sub">${t("web.sub.gpu")}</p>`;
      const options = GPUS.map((g) => ({ name: t(g.k), desc: t(g.d), value: g.value }));
      const g = cardGrid(options, (o) => (state.GPU = o.value));
      el.appendChild(g);
    },
    valid: () => !!state.GPU,
  };
}

function userStep() {
  return {
    label: "web.step.user",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.user")}</h2>`;
      el.appendChild(
        h([
          { label: "web.user.user", value: state.INSTALL_USER, oninput: (v) => (state.INSTALL_USER = v) },
          { label: "web.user.host", value: state.HOSTNAME, oninput: (v) => (state.HOSTNAME = v) },
          { label: "web.user.pass", type: "password", oninput: (v) => (state.INSTALL_USER_PASS = v) },
          { label: "web.user.confirm", type: "password", oninput: (v) => (state._uconf = v) },
        ])
      );
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.id = "root-same";
      cb.checked = state.ROOT_SAME !== false;
      const lab = document.createElement("label");
      lab.htmlFor = "root-same";
      lab.className = "check-row";
      const txt = document.createElement("span");
      txt.textContent = t("web.user.sameroot");
      lab.append(cb, txt);
      el.appendChild(lab);
      const rootBox = document.createElement("div");
      el.appendChild(rootBox);
      const sync = () => {
        rootBox.innerHTML = "";
        if (state.ROOT_SAME) {
          state.ROOT_PASS = "";
        } else {
          rootBox.appendChild(
            h([{ label: "web.user.root", type: "password", value: state.ROOT_PASS, oninput: (v) => (state.ROOT_PASS = v) }])
          );
        }
      };
      cb.addEventListener("change", () => {
        state.ROOT_SAME = cb.checked;
        sync();
      });
      sync();
    },
    valid: () =>
      !!state.INSTALL_USER &&
      !!state.INSTALL_USER_PASS &&
      state.INSTALL_USER_PASS === state._uconf &&
      (state.ROOT_SAME !== false || !!state.ROOT_PASS),
  };
}

function summaryStep() {
  return {
    label: "web.step.summary",
    render(el) {
      const rows = [
        [t("s.disk"), state.INSTALL_DISK],
        [t("s.fs"), state.FS_TYPE],
        [t("s.locale"), state.LOCALE],
        [t("s.keymap"), state.KEYMAP],
        [t("s.zone"), state.ZONEINFO],
        [t("s.mirror"), state.MIRROR || t("mirror.auto")],
        [t("s.type"), state.OFFLINE === "1" ? t("type.offline") : t("type.online")],
        [t("s.luks"), state.USE_LUKS === "1" ? t("web.luks.luks2") : t("no")],
        [t("s.gpu"), t(GPU_NAME[state.GPU] || "web.gpu.auto")],
        [t("s.hostname"), state.HOSTNAME],
        [t("s.user"), state.INSTALL_USER],
      ];
      el.innerHTML = `<h2>${t("summary")}</h2>`;
      const s = document.createElement("div");
      s.className = "summary";
      rows.forEach(([k, v]) => {
        const r = document.createElement("div");
        r.className = "row";
        r.innerHTML = `<span class="k">${k}</span><span class="v">${v}</span>`;
        s.appendChild(r);
      });
      el.appendChild(s);
      const w = document.createElement("div");
      w.className = "warn-box";
      w.textContent = t("web.warn.disk");
      el.appendChild(w);
    },
    valid: () => true,
    submit() {
      startInstall();
    },
  };
}

steps.push(
  localeStep(),
  diskStep(),
  fsStep(),
  keymapStep(),
  mirrorStep(),
  typeStep(),
  luksStep(),
  gpuStep(),
  userStep(),
  summaryStep()
);

/* ---------- instalação ---------- */
const STAGES = [
  "stage.lang_key",
  "stage.mirror",
  "stage.disk",
  "stage.fs",
  "stage.copy",
  "stage.chroot",
  "stage.boot",
  "stage.final",
];
const STAGE_THRESH = [8, 12, 25, 35, 55, 70, 90, 100];
const RING_CIRC = 2 * Math.PI * 88;

let curPct = 0;
let tweenRaf = null;

function tweenPct(targetPct) {
  if (tweenRaf) cancelAnimationFrame(tweenRaf);
  $("#ring-fg").style.transition = "none";
  const frame = () => {
    const diff = targetPct - curPct;
    if (Math.abs(diff) <= 0.1) {
      curPct = targetPct;
      tweenRaf = null;
      $("#ring-fg").style.transition = "stroke-dashoffset .3s cubic-bezier(.4, 0, .2, 1)";
    } else {
      curPct += diff * 0.22;
      tweenRaf = requestAnimationFrame(frame);
    }
    $("#ring-pct").textContent = Math.round(curPct) + "%";
    $("#ring-fg").style.strokeDashoffset = String(RING_CIRC - (RING_CIRC * curPct) / 100);
  };
  frame();
}

function enterDone(imgUrl) {
  const img = $("#done-img");
  const go = () => show("done");
  if (img.getAttribute("src") === imgUrl) return go();
  img.onload = go;
  img.onerror = go;
  setTimeout(go, 2000);
  img.src = imgUrl;
}

function buildStages() {
  const box = $("#stage-check");
  box.innerHTML = "";
  STAGES.forEach((s) => {
    const it = document.createElement("div");
    it.className = "stage-item";
    it.innerHTML = `<span class="dot"></span><span>${t(s)}</span>`;
    box.appendChild(it);
  });
}

function pump(aborted) {
  $("#log-box").textContent = aborted.lines.join("\n");
  const box = $("#log-box");
  box.scrollTop = box.scrollHeight;
  document.querySelectorAll(".stage-item").forEach((it, i) => {
    const th = STAGE_THRESH[i];
    it.classList.toggle("done", !aborted.aborted && aborted.pct >= th);
    it.classList.toggle("current", !aborted.aborted && i < STAGES.length - 1 && aborted.pct >= (i === 0 ? 2 : STAGE_THRESH[i - 1]) && aborted.pct < th);
  });
}

async function startInstall() {
  await loadI18n(state.NLLANG || UI_LANG);
  if (state.ROOT_SAME) state.ROOT_PASS = state.INSTALL_USER_PASS;
  show("installing");
  document.querySelector(".install-title").textContent = t("tui.installing");
  document.querySelector(".logs summary").textContent = t("web.logs");
  buildStages();
  const aborted = { pct: 0, lines: [], aborted: false };
  $("#ring-pct").textContent = "0%";
  curPct = 0;
  if (tweenRaf) cancelAnimationFrame(tweenRaf);
  $("#ring-fg").style.strokeDashoffset = RING_CIRC;
  $("#stage-label").textContent = t("web.start");
  $("#btn-done").removeAttribute("data-ok");
  $("#done").classList.remove("err");
  $("#done-img").src = "/static/logo.png";
  $("#btn-reboot").style.display = "none";

  const src = new EventSource("/api/stream");
  src.addEventListener("progress", (ev) => {
    const d = JSON.parse(ev.data);
    aborted.pct = d.pct;
    aborted.aborted = false;
    $("#ring-fg").style.transition = "stroke-dashoffset .3s cubic-bezier(.4, 0, .2, 1)";
    tweenPct(d.pct);
    $("#stage-label").textContent = d.label;
    pump(aborted);
  });
  src.addEventListener("tail", (ev) => {
    const d = JSON.parse(ev.data);
    $("#live-tail").textContent = d.line;
  });
  src.addEventListener("log", (ev) => {
    const d = JSON.parse(ev.data);
    aborted.lines.push(d.line);
    while (aborted.lines.length > 300) aborted.lines.shift();
    $("#log-box").textContent = aborted.lines.join("\n");
    const box = $("#log-box");
    box.scrollTop = box.scrollHeight;
  });
  src.addEventListener("done", (ev) => {
    src.close();
    const d = JSON.parse(ev.data);
    if (d.code === 0) {
      $("#done-title").textContent = t("tui.done");
      $("#done-msg").textContent = t("web.done.okmsg");
      $("#btn-reboot").textContent = t("web.done.reboot");
      $("#btn-reboot").style.display = "";
      $("#btn-done").textContent = t("web.done.close");
      $("#done").classList.remove("err");
    } else {
      $("#done-title").textContent = t("web.done.fail");
      $("#done-msg").textContent = t("web.done.failmsg");
      $("#btn-reboot").style.display = "none";
      $("#btn-done").textContent = t("web.done.close");
      $("#done").classList.add("err");
    }
    enterDone(d.code === 0 ? "/static/success.png" : "/static/error.png");
  });
  src.addEventListener("error", (ev) => {
    src.close();
    $("#done-title").textContent = t("web.done.fail");
    $("#done-msg").textContent = t("web.err.connect");
    $("#btn-reboot").style.display = "none";
    $("#done").classList.add("err");
    enterDone("/static/error.png");
  });

  fetch("/api/install", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(Object.assign({}, state)),
  }).catch((e) => {
    src.close();
    $("#done-title").textContent = t("web.done.fail");
    $("#done-msg").textContent = t("web.err.server");
    $("#btn-reboot").style.display = "none";
    $("#done").classList.add("err");
    enterDone("/static/error.png");
  });
}

/* ---------- navegação ---------- */
$("#splash").addEventListener("click", () => {
  show("wizard");
  render();
});

window.addEventListener("keydown", (ev) => {
  if (ev.key === "Enter" && $("#wizard").classList.contains("active")) next();
});

const nextBtn = $("#btn-next");
const backBtn = $("#btn-back");
async function next() {
  const step = steps[idx];
  if (!step.valid()) {
    const m = $("#step-msg");
    if (m) {
      m.textContent = t("web.required");
      m.hidden = false;
    }
    return;
  }
  const m = $("#step-msg");
  if (m) m.hidden = true;
  if (idx === steps.length - 1) {
    step.submit();
    return;
  }
  idx += 1;
  await loadI18n(state.NLLANG);
  render();
}
nextBtn.addEventListener("click", next);
backBtn.addEventListener("click", async () => {
  if (idx > 0) {
    hideMsg();
    idx -= 1;
    await loadI18n(state.NLLANG);
    render();
  }
});
$("#btn-done").addEventListener("click", () => {
  if (!confirm(t("tui.cancel"))) return;
  try {
    fetch("/api/quit", { method: "POST" });
  } catch (e) {}
  window.close();
});
$("#btn-reboot").addEventListener("click", () => {
  if (!confirm(t("web.reboot.confirm"))) return;
  try {
    fetch("/api/reboot", { method: "POST" });
  } catch (e) {}
});

// Pré-carrega logo/sucesso/erro para não piscar a imagem errada ao concluir.
["/static/logo.png", "/static/success.png", "/static/error.png"].forEach((p) => {
  const im = new Image();
  im.src = p;
});

(async () => {
  await loadI18n(state.NLLANG);
  render();
  setTimeout(() => show("wizard"), 3600);
})();