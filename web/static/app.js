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
  DUAL_RESIZE_PARTITION: "",
  DUAL_RESIZE_BYTES: 0,
  DUAL_ROOT_SPACE_BYTES: 0,
  FS_TYPE: "",
  LOCALE: "",
  KEYMAP: "",
  ZONEINFO: "",
  INSTALL_MODE: "",
  MIRROR: "",
  MIRROR_PICKED: true,
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
let DISKS = [];
const GIB = 1024 ** 3;
const MIB = 1024 ** 2;

function hideMsg() {
  const m = $("#step-msg");
  if (m) m.hidden = true;
}

function cardGrid(options, pick, extra, selMatch) {
  const wrap = document.createElement("div");
  wrap.className = "grid";
  options.forEach((o) => {
    const c = document.createElement("div");
    c.className = "card";
    c.innerHTML =
      `<div class="check">✓</div>` +
      (o.flag ? `<span class="flag">${o.flag}</span>` : "") +
      `<div><div class="title">${o.name}</div>` +
      (o.desc ? `<div class="desc">${o.desc}</div>` : "") +
      `</div>`;
    const isSel = selMatch ? () => selMatch(o) : () => (typeof o.sel === "function" ? o.sel() : false);
    if (isSel()) c.classList.add("selected");
    c.addEventListener("click", () => {
      hideMsg();
      wrap.querySelectorAll(".card").forEach((x) => x.classList.remove("selected"));
      c.classList.add("selected");
      pick(o);
      (extra || (() => {}))(o);
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
    if (inp.type === "password") inp.autocomplete = "new-password";
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
    require: "option",
    async render(el) {
      el.innerHTML = `<h2>${t("web.step.disk")}</h2><p class="sub">${t("web.sub.disk")}</p>`;
      const grid = document.createElement("div");
      grid.className = "grid";
      el.appendChild(grid);
      try {
        const r = await fetch("/api/disks");
        const data = await r.json();
        const disks = data.disks || [];
        DISKS = disks;
        if (!disks.length) {
          grid.innerHTML = `<div class="warn-box">${t("web.disk.none")}</div>`;
          return;
        }
        disks.forEach((d) => {
          const c = document.createElement("div");
          c.className = "card";
          const freeGiB = d.free > 0 ? d.free / (1024 ** 3) : null;
          const meta = [];
          if (d.esp) meta.push(t("disk.esp"));
          if (freeGiB !== null && freeGiB >= 0.001) {
            const txt = freeGiB >= 0.1
              ? `${freeGiB.toFixed(1)} GiB ${t("disk.free")}`
              : `${Math.round(d.free / (1024 ** 2))} MiB ${t("disk.free")}`;
            meta.push(txt);
          }
          const metaHtml = meta.length ? `<div class="meta">${meta.join(" · ")}</div>` : "";
          c.innerHTML =
            `<div class="check">✓</div>` +
            `<div><div class="title">${d.name}</div>` +
            `<div class="desc">${d.size} — ${d.model || "disk"}</div>${metaHtml}</div>`;
          if (d.name === state.INSTALL_DISK) c.classList.add("selected");
          c.addEventListener("click", () => {
            grid.querySelectorAll(".card").forEach((x) => x.classList.remove("selected"));
            c.classList.add("selected");
            if (state.INSTALL_DISK !== d.name) {
              state.DUAL_RESIZE_PARTITION = "";
              state.DUAL_RESIZE_BYTES = 0;
              state.DUAL_ROOT_SPACE_BYTES = 0;
            }
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

function closeResizeDialog() {
  const overlay = $("#resize-modal");
  overlay.classList.remove("open");
  setTimeout(() => { overlay.hidden = true; }, 250);
}

async function openResizeDialog() {
  const overlay = $("#resize-modal");
  const detail = $("#resize-detail");
  const partitionSelect = $("#resize-partition");
  const slider = $("#resize-range");
  const save = $("#resize-save");
  $("#resize-title").textContent = t("web.resize.title");
  $("#resize-help").textContent = t("web.resize.help");
  document.querySelector('label[for="resize-partition"]').textContent = t("web.resize.partition");
  document.querySelector('label[for="resize-range"]').textContent = t("web.resize.capacity");
  $("#resize-note").textContent = t("web.resize.note");
  $("#resize-cancel").textContent = t("web.reboot.no");
  save.textContent = t("web.resize.save");
  $("#resize-cancel").onclick = closeResizeDialog;
  overlay.onclick = (event) => {
    if (event.target === overlay) closeResizeDialog();
  };
  detail.textContent = t("web.resize.loading");
  partitionSelect.replaceChildren();
  slider.disabled = true;
  save.disabled = true;
  overlay.hidden = false;
  requestAnimationFrame(() => overlay.classList.add("open"));

  let partitions;
  try {
    const response = await fetch(`/api/ntfs-partitions?disk=${encodeURIComponent(state.INSTALL_DISK)}`);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || t("web.resize.error"));
    partitions = data.partitions || [];
  } catch (error) {
    detail.textContent = `${t("web.resize.error")} ${error.message}`;
    return;
  }

  const resizable = partitions.filter((part) => part.resizable && part.max_shrink >= 8 * GIB + 2 * MIB);
  if (!resizable.length) {
    const reason = partitions.find((part) => part.error)?.error;
    detail.textContent = reason
      ? `${t("web.resize.error")} ${reason}`
      : partitions.length ? t("web.resize.none") : t("web.resize.no_ntfs");
    return;
  }

  resizable.forEach((part) => {
    const option = document.createElement("option");
    option.value = part.path;
    option.textContent = `${part.label} (${(part.size / GIB).toFixed(1)} GiB)`;
    partitionSelect.appendChild(option);
  });

  const selected = resizable.find((part) => part.path === state.DUAL_RESIZE_PARTITION) || resizable[0];
  partitionSelect.value = selected.path;
  const refresh = () => {
    const part = resizable.find((item) => item.path === partitionSelect.value);
    if (!part) return;
    const minGiB = 8;
    const maxGiB = Math.floor((part.max_shrink - 2 * MIB) / (GIB / 2)) / 2;
    if (maxGiB < minGiB) {
      detail.textContent = t("web.resize.none");
      slider.disabled = true;
      save.disabled = true;
      return;
    }
    const defaultGiB = Math.min(maxGiB, Math.max(minGiB, 40));
    slider.min = String(minGiB);
    slider.max = String(maxGiB);
    slider.step = "0.5";
    slider.value = String(Math.min(maxGiB, Math.max(minGiB,
      state.DUAL_RESIZE_PARTITION === part.path && state.DUAL_ROOT_SPACE_BYTES
        ? Math.round(state.DUAL_ROOT_SPACE_BYTES / GIB * 2) / 2
        : defaultGiB)));
    slider.disabled = false;
    save.disabled = false;
    const updateDetail = () => {
      const rootGiB = Number(slider.value);
      const shrinkBytes = Math.round(rootGiB * GIB) + 2 * MIB;
      const remainingWindows = Math.max(0, part.size - shrinkBytes);
      detail.textContent = `${t("web.resize.capacity")}: ${rootGiB.toFixed(1)} GiB NLinux · ` +
        `${t("web.resize.remaining")}: ${(remainingWindows / GIB).toFixed(1)} GiB Windows`;
    };
    slider.oninput = updateDetail;
    updateDetail();
  };
  partitionSelect.onchange = refresh;
  refresh();
  save.onclick = () => {
    const part = resizable.find((item) => item.path === partitionSelect.value);
    if (!part) return;
    const rootBytes = Math.round(Number(slider.value) * GIB);
    const shrinkBytes = rootBytes + 2 * MIB;
    state.DUAL_RESIZE_PARTITION = part.path;
    state.DUAL_RESIZE_BYTES = shrinkBytes;
    state.DUAL_ROOT_SPACE_BYTES = rootBytes;
    closeResizeDialog();
    render();
  };
}

function modeStep() {
  return {
    label: "web.step.mode",
    require: "option",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.mode")}</h2><p class="sub">${t("web.sub.mode")}</p>`;
      const warn = document.createElement("div");
      warn.className = "warn-box";
      warn.hidden = true;
      const resizeButton = document.createElement("button");
      resizeButton.className = "card resize-option";
      resizeButton.hidden = true;
      resizeButton.disabled = true;
      resizeButton.type = "button";
      const resizeTitle = document.createElement("div");
      resizeTitle.className = "title";
      resizeTitle.textContent = t("web.resize.open");
      const resizeDescription = document.createElement("div");
      resizeDescription.className = "desc";
      resizeDescription.textContent = t("web.resize.card_hint");
      resizeButton.append(resizeTitle, resizeDescription);
      resizeButton.addEventListener("click", openResizeDialog);
      const options = [
        { name: t("mode.wipe"), desc: t("mode.wipe.desc"), value: "wipe", sel: () => state.INSTALL_MODE === "wipe" },
        { name: t("mode.dual"), desc: t("mode.dual.desc"), value: "dual", sel: () => state.INSTALL_MODE === "dual" },
      ];
      const refreshWarn = (mode) => {
        resizeButton.hidden = mode !== "dual";
        resizeButton.disabled = !state.INSTALL_DISK;
        if (mode !== "dual") { warn.hidden = true; return; }
        const d = DISKS.find((x) => x.name === state.INSTALL_DISK);
        if (d && !d.dual_ok && !state.DUAL_RESIZE_BYTES) {
          warn.hidden = false;
          warn.textContent = d.esp ? t("mode.warn.space") : t("mode.warn.esp");
        } else {
          warn.hidden = true;
        }
      };
      const optionGrid = cardGrid(options, (o) => {
        state.INSTALL_MODE = o.value;
        if (o.value !== "dual") {
          state.DUAL_RESIZE_PARTITION = "";
          state.DUAL_RESIZE_BYTES = 0;
          state.DUAL_ROOT_SPACE_BYTES = 0;
        }
        refreshWarn(o.value);
      });
      optionGrid.classList.add("mode-options");
      optionGrid.appendChild(resizeButton);
      el.appendChild(optionGrid);
      el.appendChild(warn);
      refreshWarn(state.INSTALL_MODE);
    },
    valid: () => {
      if (!state.INSTALL_MODE) return false;
      if (state.INSTALL_MODE !== "dual") return true;
      const d = DISKS.find((x) => x.name === state.INSTALL_DISK);
      if (!d || !d.esp) return false;
      return d.dual_ok || (state.DUAL_RESIZE_BYTES > 0 && state.DUAL_ROOT_SPACE_BYTES > 5 * GIB);
    },
  };
}

function fsStep() {
  return {
    label: "web.step.fs",
    require: "option",
    render(el) {
      const options = [
        { name: "ext4", desc: t("fs.ext4d"), value: "ext4", sel: () => state.FS_TYPE === "ext4" },
        { name: "btrfs", desc: t("fs.btrfsd"), value: "btrfs", sel: () => state.FS_TYPE === "btrfs" },
      ];
      el.innerHTML = `<h2>${t("web.step.fs")}</h2><p class="sub">${t("web.sub.fs")}</p>`;
      const g = cardGrid(options, (o) => (state.FS_TYPE = o.value));
      el.appendChild(g);
    },
    valid: () => !!state.FS_TYPE,
  };
}

function localeStep() {
  return {
    label: "web.step.locale",
    require: "option",
    render(el) {
      el.innerHTML =
        `<div class="welcome-hero">` +
        `<h1 id="welcome-anim" class="welcome-anim">${WELCOMES[0]}</h1>` +
        `<div class="brand"><div class="logo-ring">` +
        `<span class="pulse"></span><span class="pulse delay-1"></span>` +
        `<div class="logo-circle"><img src="/static/logo.png" alt="NLinux"></div>` +
        `</div></div>` +
        `</div>`;
      // Uma única escolha define idioma, teclado e fuso horário juntos.
      const g = cardGrid(LOCALES, (o) => {
        state.LOCALE = o.locale;
        state.KEYMAP = o.keymap;
        state.ZONEINFO = o.zone;
        state.NLLANG = LANG_FROM_LOCALE[o.locale] || "pt";
        loadI18n(state.NLLANG);
      }, null, (o) => state.LOCALE === o.locale);
      el.appendChild(g);
    },
    valid: () => !!state.LOCALE,
  };
}

function mirrorStep() {
  return {
    label: "web.step.mirror",
    require: "option",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.mirror")}</h2><p class="sub">${t("web.sub.mirror")}</p>`;
      const g = cardGrid(MIRRORS, (o) => {
        state.MIRROR = o.value;
        state.MIRROR_PICKED = true;
      }, null, (o) => state.MIRROR === o.value);
      el.appendChild(g);
    },
    valid: () => state.MIRROR_PICKED === true,
  };
}

function typeStep() {
  return {
    label: "web.step.type",
    require: "option",
    render(el) {
      const options = [
        { name: t("type.offline"), desc: t("type.offline.sub"), value: "1", sel: () => state.OFFLINE === "1" },
        { name: t("type.online"), desc: t("type.online.sub"), value: "0", sel: () => state.OFFLINE === "0" },
      ];
      el.innerHTML = `<h2>${t("web.step.type")}</h2><p class="sub">${t("web.sub.type")}</p>`;
      const g = cardGrid(options, (o) => (state.OFFLINE = o.value));
      el.appendChild(g);
    },
    valid: () => state.OFFLINE === "0" || state.OFFLINE === "1",
  };
}

function luksStep() {
  return {
    label: "web.step.luks",
    require: "option",
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
    reason: () => {
      if (state.USE_LUKS === "0") return "";
      if (!state.LUKS_PASS) return t("pass.luks.required");
      if (state.LUKS_PASS !== state._luk_conf) return t("pass.mismatch");
      return "";
    },
  };
}

function gpuStep() {
  return {
    label: "web.step.gpu",
    require: "option",
    render(el) {
      el.innerHTML = `<h2>${t("web.step.gpu")}</h2><p class="sub">${t("web.sub.gpu")}</p>`;
      const options = GPUS.map((g) => ({ name: t(g.k), desc: t(g.d), value: g.value }));
      const g = cardGrid(options, (o) => (state.GPU = o.value), null, (o) => state.GPU === o.value);
      el.appendChild(g);
    },
    valid: () => !!state.GPU,
  };
}

function userStep() {
  return {
    label: "web.step.user",
    require: "field",
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
    reason: () => {
      if (!state.INSTALL_USER) return t("user.required");
      if (!state.INSTALL_USER_PASS) return t("pass.required");
      if (state.INSTALL_USER_PASS !== state._uconf) return t("pass.mismatch");
      if (state.ROOT_SAME === false && !state.ROOT_PASS) return t("pass.root.required");
      return "";
    },
  };
}

function summaryStep() {
  return {
    label: "web.step.summary",
    render(el) {
      const rows = [
        [t("s.disk"), state.INSTALL_DISK],
        [t("s.mode"), state.INSTALL_MODE === "dual" ? t("mode.dual") : t("mode.wipe")],
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
      if (state.DUAL_RESIZE_BYTES > 0) {
        rows.push([
          t("web.resize.partition"),
          `${state.DUAL_RESIZE_PARTITION} · ${(state.DUAL_ROOT_SPACE_BYTES / GIB).toFixed(1)} GiB`,
        ]);
      }
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
      w.textContent = state.INSTALL_MODE === "dual" ? t("web.warn.dual") : t("web.warn.disk");
      el.appendChild(w);
    },
    valid: () => true,
    async submit() {
      if (state.DUAL_RESIZE_BYTES > 0) {
        await loadI18n(state.NLLANG || UI_LANG);
        const confirmed = await askModal({
          title: t("web.resize.confirm.title"),
          msg: `${t("web.resize.confirm.message")} ${t("web.resize.partition")}: ` +
            `${state.DUAL_RESIZE_PARTITION} · ${(state.DUAL_ROOT_SPACE_BYTES / GIB).toFixed(1)} GiB.`,
          ok: t("web.resize.confirm.ok"),
          cancel: t("web.reboot.no"),
          danger: true,
        });
        if (!confirmed) return;
      }
      startInstall();
    },
  };
}

steps.push(
  localeStep(),
  diskStep(),
  modeStep(),
  fsStep(),
  mirrorStep(),
  typeStep(),
  luksStep(),
  gpuStep(),
  userStep(),
  summaryStep()
);

/* ---------- instalação ---------- */
const RING_CIRC = 2 * Math.PI * 88;

/* Plano de etapas usado só como reserva: o install.sh manda o plano real
   (NLSTEPS) e ele é diferente entre os modos offline e online. A lista abaixo
   existe para o painel não ficar vazio se o log ainda não trouxer o plano.
   O número é o ponto em que a etapa começa; a distância entre duas etapas é o
   peso dela — é o mesmo plano que o install.sh manda. */
const FALLBACK_STEPS = {
  offline: [
    [0, "stage.lang_key"], [2, "stage.mirror"], [4, "stage.disk"], [9, "stage.fs"],
    [13, "stage.copy.offline"], [72, "stage.chroot.system"], [85, "stage.chroot.desktop"],
    [96, "stage.boot"], [99, "stage.final"],
  ],
  online: [
    [0, "stage.lang_key"], [2, "stage.mirror"], [4, "stage.disk"], [9, "stage.fs"],
    [13, "stage.pac.download"], [38, "stage.chroot.system"], [54, "stage.chroot.aur"],
    [85, "stage.chroot.desktop"], [96, "stage.boot"], [99, "stage.final"],
  ],
};

let curPct = 0;
let tweenRaf = null;

/* Cópia local do estado da execução mostrada na tela. Quem manda é o servidor:
   o SSE atualiza `run` e, a cada (re)conexão, o evento `state` devolve o
   quadro completo (etapas, %, últimas linhas, contadores de download). */
const run = {
  pct: 0, lines: [], label: "", act: "", done: false, code: null,
  steps: [], step: "", stepSig: "", idx: -1, mode: "", started: 0, finished: 0,
  download: { bytes: 0, rate: 0, files: 0, total: 0 },
};
let src = null;
let watchdog = null;
let logRaf = null;
let lastLogText = null;
let installRequested = false;
let clockTimer = null;
let streamDown = false;

function tweenPct(targetPct) {
  if (tweenRaf) cancelAnimationFrame(tweenRaf);
  $("#ring-fg").style.transition = "none";
  const frame = () => {
    const diff = targetPct - curPct;
    if (Math.abs(diff) <= 0.5) {
      curPct = targetPct;
      tweenRaf = null;
      $("#ring-fg").style.transition = "stroke-dashoffset .3s cubic-bezier(.4, 0, .2, 1)";
    } else {
      curPct += diff * 0.35;
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
  run.steps.forEach((s) => {
    const it = document.createElement("div");
    it.className = "stage-item";
    it.dataset.pct = String(s.pct);
    const label = document.createElement("span");
    label.textContent = s.label;
    it.innerHTML = '<span class="dot"></span>';
    it.appendChild(label);
    box.appendChild(it);
  });
}

/* Lista de etapas na ordem em que o instalador realmente executa (vem do
   install.sh, via NLSTEPS). A etapa atual é a que o servidor está anunciando
   (run.idx): ela não é deduzida da porcentagem, porque o anel anda sozinho
   dentro da etapa e passaria à frente da lista. Sem o índice do servidor
   (plano antigo), cai para a comparação com a porcentagem. */
function renderSteps() {
  const box = $("#stage-check");
  if (!box.children.length && run.steps.length) buildStages();
  const items = box.querySelectorAll(".stage-item");
  if (!items.length) return;
  let current = run.idx;
  if (current < 0) {
    items.forEach((it, i) => {
      if (Number(it.dataset.pct) <= run.pct) current = i;
    });
  }
  const finished = run.pct >= 100;
  items.forEach((it, i) => {
    it.classList.toggle("done", i < current || (finished && i <= current));
    it.classList.toggle("current", !finished && i === current);
  });
}

/* Log: redesenha o <pre> no máximo uma vez por frame. Durante os builds AUR
   chegam centenas de linhas por segundo; redesenhar a cada linha trava o
   renderizador, o navegador deixa de ler o stream e a conexão cai. */
function scheduleLog() {
  if (logRaf) return;
  logRaf = requestAnimationFrame(() => {
    logRaf = null;
    const text = run.lines.join("\n");
    if (text === lastLogText) return;
    lastLogText = text;
    const box = $("#log-box");
    box.textContent = text;
    box.scrollTop = box.scrollHeight;
  });
}

function addLines(lines) {
  for (const l of lines) run.lines.push(l);
  if (run.lines.length > 300) run.lines.splice(0, run.lines.length - 300);
  scheduleLog();
}

/* Texto abaixo do anel: a etapa (ou a nota dela) e, quando existe, o que está
   acontecendo agora — "Baixar e compilar pacotes da AUR · Compilando
   umbriel-git". A atividade vem do servidor já traduzida. */
function setLabel(text, act) {
  $("#stage-label").textContent = act ? `${text} · ${act}` : text;
}

/* ---------- relógio digital ---------- */
/* Seis dígitos (H:MM:SS) montados uma vez; cada dígito é uma fita 0-9 que
   recebe um translateY quando o número muda — é isso que dá a animação. */
const CLOCK_DIGITS = 6;
/* Passo da fita, em rem: tem de ser a MESMA medida que a altura/line-height da
   janela no style.css (2rem). É em rem, e não em em, porque o navegador resolve
   `em` por dois caminhos diferentes — o height da caixa passa pelo font-size
   arredondado e o translateY não — e aí a fita anda um pouco diferente da
   janela, um pouquinho mais a cada dígito, e um deles acaba alguns milímetros
   fora da linha dos outros. */
const DIGIT_STEP = 2;
const clockSlots = [];

function buildClock() {
  const box = $("#clock-digits");
  box.innerHTML = "";
  clockSlots.length = 0;
  for (let i = 0; i < CLOCK_DIGITS; i++) {
    // H:MM:SS — separadores antes do 3º e do 5º dígito.
    if (i === 2 || i === 4) {
      const sep = document.createElement("span");
      sep.className = "sep";
      sep.textContent = ":";
      box.appendChild(sep);
    }
    const slot = document.createElement("span");
    slot.className = "digit";
    const strip = document.createElement("i");
    for (let n = 0; n < 10; n++) {
      const d = document.createElement("span");
      d.textContent = String(n);
      strip.appendChild(d);
    }
    slot.appendChild(strip);
    box.appendChild(slot);
    // Fita já posicionada no zero: o primeiro paint não "pula" e todo dígito
    // tem um valor explícito (importa para quem lê o DOM).
    strip.dataset.v = "0";
    strip.style.transform = "translateY(0rem)";
    clockSlots.push(strip);
  }
}

function setDigit(i, value) {
  const strip = clockSlots[i];
  if (!strip || strip.dataset.v === String(value)) return;
  strip.dataset.v = String(value);
  strip.style.transform = "translateY(" + (-value * DIGIT_STEP).toFixed(0) + "rem)";
}

/* Segundos decorridos: usa o `started` do servidor (assim o relógio não volta
   a zero se a página recarregar no meio da instalação) e, entre dois quadros
   do servidor, o relógio local para o contador não engasgar. */
function elapsedSeconds() {
  if (!run.started) return 0;
  const end = run.finished || (Date.now() / 1000);
  return Math.max(0, Math.floor(end - run.started));
}

function paintClock() {
  const total = elapsedSeconds();
  const h = Math.min(99, Math.floor(total / 3600));
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const vals = [
    Math.floor(h / 10), h % 10,
    Math.floor(m / 10), m % 10,
    Math.floor(s / 10), s % 10,
  ];
  // forEach passa (valor, índice): a ordem dos argumentos de setDigit é o
  // inverso, então o índice vem explicitamente.
  vals.forEach((v, i) => setDigit(i, v));
}

/* "1 h 23 min 41 s" / "23 min 41 s", com as unidades traduzidas. */
function formatDuration(sec) {
  sec = Math.max(0, Math.floor(sec || 0));
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  const pad = (n) => String(n).padStart(2, "0");
  const min = `${m} ${t("web.time.min")}`;
  const seg = `${pad(s)}${t("web.time.sec")}`;
  if (h > 0) return `${h} ${t("web.time.hour")} ${min} ${seg}`;
  return `${min} ${seg}`;
}

function startClock() {
  buildClock();
  paintClock();
  if (clockTimer) clearInterval(clockTimer);
  clockTimer = setInterval(paintClock, 1000);
}

function stopClock() {
  if (clockTimer) clearInterval(clockTimer);
  clockTimer = null;
}

/* ---------- monitor de download (modo online) ---------- */
function fmtNum(n, digits) {
  try {
    return Number(n).toLocaleString(UI_LANG, {
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    });
  } catch (e) {
    return Number(n).toFixed(digits);
  }
}

function showDownload(on) {
  const el = $("#dl");
  if (el) el.hidden = !on;
}

/* Linha do download (só online): tamanho total anunciado pelo pacman, quanto
   já foi baixado e a velocidade média. Todas as medidas em MB, para dá para
   comparar de relance.

   O total é do pacman (é ele quem sabe quanto vem antes de começar), e vale só
   para a etapa que está baixando: fora dela a medida some em vez de mostrar um
   número velho. A média também some quando decai para zero — um "0,0 MB/s" na
   tela depois da etapa só polui. */
function fmtMB(bytes) {
  const mb = (bytes || 0) / MIB;
  return `${fmtNum(mb, mb < 10 ? 1 : 0)} MB`;
}

function paintDownload() {
  const d = run.download || {};
  const total = $("#dl-total-cell");
  if (total) total.hidden = !(d.total > 0);
  $("#dl-total").textContent = d.total > 0 ? fmtMB(d.total) : "—";
  $("#dl-got").textContent = fmtMB(d.bytes);
  const mbs = (d.rate || 0) / MIB;
  $("#dl-rate").textContent = mbs >= 0.05 ? `${fmtNum(mbs, 1)} MB/s` : "—";
  $("#dl-files").textContent = d.files > 0
    ? `${d.files} ${t("web.dl.files")}`
    : "";
}

function applyDownload(d) {
  if (!d) return;
  run.download = {
    bytes: d.bytes || 0,
    rate: d.rate || 0,
    files: d.files || 0,
    total: d.total || 0,
  };
  showDownload(run.mode === "online" || run.mode === "");
  paintDownload();
}

function paint() {
  $("#ring-fg").style.transition = "stroke-dashoffset .3s cubic-bezier(.4, 0, .2, 1)";
  tweenPct(run.pct);
  // Com o stream fora, o rótulo é "Reconectando" e não pode ser atropelado pelo
  // progresso que ainda chega pelo watchdog.
  if (run.label && !streamDown) setLabel(run.label, run.act);
  renderSteps();
  scheduleLog();
}

function enterInstalling() {
  if (!$("#installing").classList.contains("active")) {
    show("installing");
    document.querySelector(".install-title").textContent = t("tui.installing");
    document.querySelector(".logs summary").textContent = t("web.logs");
    $("#clock-title").textContent = t("web.time.title");
    $("#clock").setAttribute("aria-label", t("web.time.title"));
    $("#dl-title").textContent = t("web.dl.title");
    $("#dl-size-label").textContent = t("web.dl.size");
    $("#dl-got-label").textContent = t("web.dl.got");
    $("#dl-avg-label").textContent = t("web.dl.avg");
    buildStages();
    startClock();
  }
  paint();
}

/* Tempo que o painel fica mostrando o anel em 100% antes de trocar para a tela
   de resultado. As três últimas etapas (desktop/boas-vindas, bootloader e
   finalização) são rápidas: o `done` chega no mesmo instante em que elas
   aportaram no log e a tela de sucesso aparecia no lugar delas, com o anel
   ainda no meio do caminho. Aqui é só apresentação — nada espera mais do que a
   instalação, e no erro a troca é na hora. */
const DONE_HOLD_MS = 1600;
let doneTimer = null;

function finishSoon(code) {
  if (doneTimer || run.done) return;
  if (code !== 0) {
    showResult(code);
    return;
  }
  // A instalação acabou com sucesso: o anel vai a 100% e a etapa corrente
  // (a última do plano, "Concluído") fica na tela por um instante.
  run.pct = 100;
  enterInstalling();
  doneTimer = setTimeout(() => {
    doneTimer = null;
    showResult(0);
  }, DONE_HOLD_MS);
}

function showResult(code) {
  if (src) {
    try { src.close(); } catch (e) {}
    src = null;
  }
  if (watchdog) {
    clearInterval(watchdog);
    watchdog = null;
  }
  run.done = true;
  run.code = code;
  stopClock();
  const total = $("#done-time");
  if (total) {
    if (run.started) {
      const secs = elapsedSeconds();
      total.innerHTML = `${t("web.time.total")}: <b>${formatDuration(secs)}</b>`;
      total.hidden = false;
    } else {
      total.hidden = true;
    }
  }
  if (code === 0) {
    $("#done-title").textContent = t("tui.done");
    $("#done-msg").textContent = t("web.done.okmsg");
    $("#btn-reboot").textContent = t("web.done.reboot");
    $("#btn-reboot").style.display = "";
    $("#btn-done").textContent = t("web.done.continue");
    $("#done").classList.remove("err");
  } else {
    $("#done-title").textContent = t("web.done.fail");
    $("#done-msg").textContent = t("web.done.failmsg");
    $("#btn-reboot").style.display = "none";
    $("#btn-done").textContent = t("web.done.close");
    $("#done").classList.add("err");
  }
  enterDone(code === 0 ? "/static/success.png" : "/static/error.png");
}

/* Aplica o quadro de estado vindo do servidor (evento `state` ou /api/status). */
function applyState(st) {
  if (!st) return;
  if (Array.isArray(st.lines) && st.lines.length) {
    run.lines = st.lines.slice(-300);
    lastLogText = null;
  }
  // Plano de etapas: o install.sh manda a lista na ordem real (e diferente
  // entre offline e online). Só a troca de lista redesenha o <div>.
  if (Array.isArray(st.steps) && st.steps.length) {
    const sig = st.steps.map((s) => `${s.pct}:${s.label}`).join("|");
    if (sig !== run.stepSig) {
      run.stepSig = sig;
      run.steps = st.steps;
      // Só redesenha aqui se já havia uma lista na tela; quando a caixa está
      // vazia quem monta é renderSteps(), chamado logo abaixo por paint().
      const box = $("#stage-check");
      if (box && box.children.length) buildStages();
    }
  } else if (!run.steps.length) {
    // Sem plano no log (execução antiga, log já rotacionado): entra a reserva
    // do próprio app. Ela também precisa redesenhar a lista, senão a caixa da
    // tela ficaria mostrando o plano da execução anterior.
    const online = st.mode === "online" || (st.mode !== "offline" && String(state.OFFLINE) === "0");
    run.stepSig = "";
    run.steps = FALLBACK_STEPS[online ? "online" : "offline"].map(([pct, key]) => ({ pct, label: t(key) }));
    const box = $("#stage-check");
    if (box && box.children.length) buildStages();
  }
  if (st.mode) {
    run.mode = st.mode;
    showDownload(st.mode === "online");
  }
  if (typeof st.started === "number" && st.started && st.started !== run.started) {
    run.started = st.started;
    // Sem isto o relógio ficaria em 00:00:00 até o próximo tique.
    if (clockSlots.length) paintClock();
  }
  if (typeof st.finished === "number" && st.finished) run.finished = st.finished;
  if (st.download) applyDownload(st.download);
  if (typeof st.pct === "number") run.pct = Math.max(run.pct, st.pct);
  if (st.label) run.label = st.label;
  if (typeof st.act === "string") run.act = st.act;
  if (typeof st.idx === "number" && st.idx >= 0) run.idx = st.idx;
  if (st.running) enterInstalling();
  // Só segura o 100% se o painel de instalação é que estava na tela: quem
  // recarrega a página já terminou de ver e quer logo a tela de resultado.
  if (st.done) {
    const code = st.code === 0 ? 0 : st.code || 1;
    if ($("#installing").classList.contains("active")) finishSoon(code);
    else showResult(code);
  }
}

async function fetchStatus() {
  try {
    const r = await fetch("/api/status", { cache: "no-store" });
    if (!r.ok) return null;
    return await r.json();
  } catch (e) {
    return null;
  }
}

/* Queda de conexão NÃO é falha de instalação: o install.sh continua rodando
   no servidor. Só marca "reconectando" — o watchdog ressincroniza. */
function onStreamDropped() {
  if (run.done) return;
  streamDown = true;
  setLabel(t("web.reconnecting"));
}

function openStream() {
  if (src) return;
  src = new EventSource("/api/stream");
  src.addEventListener("state", (ev) => {
    streamDown = false;
    applyState(JSON.parse(ev.data));
  });
  src.addEventListener("progress", (ev) => {
    const d = JSON.parse(ev.data);
    streamDown = false;
    run.pct = Math.max(run.pct, d.pct || 0);
    run.label = d.label;
    if (typeof d.act === "string") run.act = d.act;
    if (typeof d.idx === "number" && d.idx >= 0) run.idx = d.idx;
    enterInstalling();
  });
  src.addEventListener("log", (ev) => {
    const d = JSON.parse(ev.data);
    addLines(Array.isArray(d.lines) ? d.lines : [d.line]);
  });
  src.addEventListener("download", (ev) => applyDownload(JSON.parse(ev.data)));
  src.addEventListener("done", (ev) => finishSoon(JSON.parse(ev.data).code));
  src.addEventListener("error", onStreamDropped);
}

/* Vigia a conexão: se o stream cair, sonda o servidor e, respondendo ele,
   reabre o stream (que volta com o estado `state` do progresso atual). */
function startWatchdog() {
  if (watchdog) return;
  watchdog = setInterval(async () => {
    if (run.done) return;
    if (src && src.readyState === 1) return;
    const st = await fetchStatus();
    if (!st) {
      onStreamDropped();
      return;
    }
    if (src) {
      try { src.close(); } catch (e) {}
      src = null;
    }
    openStream();
    applyState(st);
  }, 4000);
}

async function startInstall() {
  if (installRequested) return;
  installRequested = true;
  await loadI18n(state.NLLANG || UI_LANG);
  if (state.ROOT_SAME) state.ROOT_PASS = state.INSTALL_USER_PASS;
  run.lines = [];
  run.pct = 0;
  run.label = "";
  run.act = "";
  run.done = false;
  run.code = null;
  run.steps = [];
  run.stepSig = "";
  run.idx = -1;
  run.started = 0;
  run.finished = 0;
  run.download = { bytes: 0, rate: 0, files: 0, total: 0 };
  // Uma instalação nova cancela a espera da anterior (se é que ela chegou a
  // esperar): senão a tela de sucesso do run velho entra no meio do painel.
  if (doneTimer) {
    clearTimeout(doneTimer);
    doneTimer = null;
  }
  // O modo vem do assistente: o monitor de download só existe no online.
  run.mode = String(state.OFFLINE) === "1" ? "offline" : "online";
  showDownload(run.mode === "online");
  lastLogText = null;
  enterInstalling();
  curPct = 0;
  if (tweenRaf) cancelAnimationFrame(tweenRaf);
  tweenRaf = null;
  $("#ring-pct").textContent = "0%";
  $("#ring-fg").style.strokeDashoffset = RING_CIRC;
  setLabel(t("web.start"));
  $("#btn-done").removeAttribute("data-ok");
  $("#done").classList.remove("err");
  $("#done-img").src = "/static/logo.png";
  $("#btn-reboot").style.display = "none";
  $("#done-time").hidden = true;
  openStream();
  startWatchdog();

  try {
    const r = await fetch("/api/install", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(Object.assign({}, state)),
    });
    if (r.status === 409) {
      // Já existe instalação em andamento (pedido duplicado ou página
      // recarregada): volta para o painel dela em vez de apagar o disco.
      const d = await r.json().catch(() => ({}));
      applyState(d.state || (await fetchStatus()));
      return;
    }
    if (!r.ok) {
      const d = await r.json().catch(() => ({}));
      if (d.error) console.error(d.error);
      showResult(1);
    }
  } catch (e) {
    // Falha de rede no pedido: a instalação pode ter começado mesmo assim —
    // consulta o estado em vez de declarar erro.
    const st = await fetchStatus();
    if (st && (st.running || st.pct > 0 || st.done)) {
      applyState(st);
      return;
    }
    showResult(1);
  }
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
    let msg = step.require === "field" ? t("web.required.field") : t("web.required.option");
    if (typeof step.reason === "function") {
      const r = step.reason();
      if (r) msg = r;
    }
    const m = $("#step-msg");
    if (m) {
      m.textContent = msg;
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
$("#btn-done").addEventListener("click", async () => {
  const confirmed = await askModal({
    title: t("web.done.close"),
    msg: t("tui.cancel"),
    ok: t("web.done.close"),
    cancel: t("web.reboot.no"),
    danger: true,
    icon: "close",
  });
  if (!confirmed) return;
  try {
    fetch("/api/quit", { method: "POST" });
  } catch (e) {}
  window.close();
});

// Modal de confirmação estilizado (substitui o confirm() nativo).
function askModal({ title, msg, ok, cancel, danger = false, icon = "restart" }) {
  return new Promise((resolve) => {
    const m = $("#modal");
    const iconPaths = icon === "close"
      ? ["M18 6 6 18M6 6l12 12"]
      : [
          "M21 2v6h-6",
          "M3 12a9 9 0 0 1 15.36-6.36L21 8",
          "M3 22v-6h6",
          "M21 12a9 9 0 0 1-15.36 6.36L3 16",
        ];
    const iconSvg = m.querySelector(".modal-icon svg");
    iconSvg.replaceChildren(...iconPaths.map((d) => {
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      return path;
    }));
    $("#modal-title").textContent = title;
    $("#modal-msg").textContent = msg;
    $("#modal-ok").textContent = ok;
    $("#modal-ok").classList.toggle("danger", danger);
    $("#modal-cancel").textContent = cancel;
    m.hidden = false;
    m.classList.remove("spinning");
    requestAnimationFrame(() => m.classList.add("open"));
    const close = (res) => {
      m.classList.remove("open");
      setTimeout(() => { m.hidden = true; resolve(res); }, 250);
    };
    $("#modal-cancel").onclick = () => close(false);
    $("#modal-ok").onclick = () => close(true);
  });
}

function spinModal(msg) {
  const m = $("#modal");
  $("#modal-title").textContent = "";
  $("#modal-msg").textContent = msg;
  m.classList.add("spinning");
}

$("#btn-reboot").addEventListener("click", async () => {
  const ok1 = await askModal({
    title: t("web.reboot.title"),
    msg: t("web.reboot.confirm"),
    ok: t("web.done.reboot"),
    cancel: t("web.reboot.no"),
    danger: true,
  });
  if (!ok1) return;
  spinModal(t("web.reboot.pending"));
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
  // Instalação já em andamento (página recarregada, navegador reconectando ou
  // servidor reanexado após uma queda): volta direto ao painel em vez do
  // assistente — assim ninguém reinicia a instalação por cima da que roda.
  let st = await fetchStatus();
  if (st && st.lang) {
    state.NLLANG = st.lang;
    await loadI18n(st.lang);
  }
  if (st && (st.running || st.done)) {
    installRequested = true;
    openStream();
    startWatchdog();
    // O próprio applyState cuida do resto (etapas, modo, relógio, download) e
    // abre o painel ou a tela de resultado.
    applyState(st);
    return;
  }
  setTimeout(() => show("wizard"), 3600);
})();