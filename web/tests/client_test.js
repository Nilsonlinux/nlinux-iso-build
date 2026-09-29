/* Testes do web/static/app.js: o painel (anel, lista de etapas e a linha
   "etapa · atividade") rodando de verdade no jsdom, com o app.js inteiro
   carregado no DOM do index.html.

     cd web/tests && npm install && node client_test.js

   O `npm install` é só uma vez: traz o jsdom. Sem node/npm, rode as suítes
   Python por `web/tests/run-tests.sh` (só elas são obrigatórias).
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { JSDOM } = require("jsdom");

// web/tests/ -> web/ -> static/
const STATIC = path.join(__dirname, "..", "static");
const app = fs.readFileSync(path.join(STATIC, "app.js"), "utf8");
const html = fs.readFileSync(path.join(STATIC, "index.html"), "utf8");

const fails = [];
function check(name, cond, extra = "") {
  if (cond) console.log("  ok   " + name);
  else {
    console.log("  FAIL " + name + " -> " + extra);
    fails.push(name);
  }
}
const eq = (name, got, want) =>
  check(name, JSON.stringify(got) === JSON.stringify(want),
        JSON.stringify(got) + " != " + JSON.stringify(want));

/* Plano que o install.sh manda (o mesmo do servidor): o número é o começo da
   etapa e a distância entre duas etapas é o peso dela. */
const PLAN_ONLINE = [
  [0, "Teclado e idioma"], [2, "Espelho"], [4, "Particionar o disco"],
  [9, "Formatar"], [13, "Baixar / instalar pacotes"],
  [38, "Preparar o sistema"], [54, "Baixar e compilar pacotes da AUR"],
  [85, "Desktop e serviços"], [96, "Bootloader"], [99, "Finalizando"],
];

/* ---------- boot: uma página do instalador ---------- */

function boot(statusReply) {
  const dom = new JSDOM(html, {
    runScripts: "dangerously",
    pretendToBeVisual: true,
    url: "http://localhost:8080/",
  });
  const { window } = dom;
  const doc = window.document;

  /* fetch: o app chama /api/i18n, /api/status, /api/install e /api/quit. */
  const fetchLog = [];
  window.fetch = (url, opts) => {
    fetchLog.push([String(url), (opts && opts.method) || "GET"]);
    const reply = (obj) =>
      Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(obj) });
    if (String(url).indexOf("/api/i18n") === 0) return reply({ lang: "pt", table: {} });
    if (String(url).indexOf("/api/status") === 0) return reply(statusReply);
    return reply({});
  };

  /* EventSource: guarda os ouvintes para o teste poder emitir os eventos. */
  const listeners = [];
  class FakeES {
    constructor(url) {
      this.url = url;
      this.readyState = 1;
      listeners.push(this);
    }
    addEventListener(name, fn) {
      (this._h || (this._h = {}))[name] = fn;
    }
    close() {
      this.readyState = 2;
    }
  }
  window.EventSource = FakeES;

  /* O app.js é um script normal: avaliando o arquivo, `const`/`let` de topo
     ficam no escopo do eval, então o epilogue é quem os expõe ao teste. */
  window.eval(app + `
;globalThis.__t = {
  run, applyState, setLabel, paint, renderSteps, buildStages, startInstall,
  stopClock, FALLBACK_STEPS,
  labels: () => ({
    label: doc.getElementById("stage-label").textContent,
    pct: doc.getElementById("ring-pct").textContent,
    tail: doc.getElementById("live-tail").textContent,
    log: doc.getElementById("log-box").textContent,
    dlHidden: doc.getElementById("dl").hidden,
  }),
  items: () => Array.from(doc.querySelectorAll("#stage-check .stage-item")).map((it) => ({
    text: it.textContent,
    pct: Number(it.dataset.pct),
    done: it.classList.contains("done"),
    current: it.classList.contains("current"),
  })),
  where: (id) => doc.querySelectorAll("section.screen").length &&
    Array.prototype.indexOf.call(doc.querySelectorAll("section.screen"),
      Array.prototype.filter.call(doc.querySelectorAll("section.screen"),
        (s) => s.id === id)[0]),
  activeScreen: () => (doc.querySelector("section.screen.active") || {}).id,
};`.replace(/doc\./g, "document."));

  const T = window.__t;
  return {
    window,
    T,
    fetchLog,
    emit(name, data) {
      const es = listeners[listeners.length - 1];
      const fn = (es && es._h && es._h[name]) || (listeners[0]._h || {})[name];
      if (!fn) throw new Error("nenhum ouvinte para o evento " + name);
      fn({ data: JSON.stringify(data) });
    },
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const st = (plan, extra) => Object.assign(
  { running: true, pct: 0, label: "", act: "", idx: 0, mode: "online", started: 1,
    steps: plan.map(([pct, label]) => ({ pct, label })) },
  extra || {});

(async function main() {
  const p = boot(st(PLAN_ONLINE));
  const T = p.T;
  await sleep(60); // o IIFE do app já rodou (consultou o /api/status)

  /* ----------------------------------------------------------------- */
  console.log("== página entra direto no painel quando já há instalação ==");
  eq("tela do painel aberta", T.activeScreen(), "installing");
  eq("lista de etapas do servidor", T.items().length, PLAN_ONLINE.length);
  eq("primeira etapa em destaque", T.items()[0].current, true);
  check("monitor de download visível no online", T.labels().dlHidden === false);

  /* ----------------------------------------------------------------- */
  console.log("== linha abaixo do anel: etapa · atividade ==");
  T.setLabel("Baixar e compilar pacotes da AUR", "Compilando yay-bin");
  eq("etapa com atividade", T.labels().label,
     "Baixar e compilar pacotes da AUR · Compilando yay-bin");
  T.setLabel("Baixar e compilar pacotes da AUR", "");
  eq("etapa sem atividade", T.labels().label, "Baixar e compilar pacotes da AUR");

  /* ----------------------------------------------------------------- */
  console.log("== evento progress ==");
  p.emit("progress", { pct: 54, label: "Baixar e compilar pacotes da AUR",
                       act: "Compilando umbriel-git", step: "stage.chroot.aur", idx: 6 });
  eq("rótulo no evento progress", T.labels().label,
     "Baixar e compilar pacotes da AUR · Compilando umbriel-git");
  check("anel recebeu a %", /^\d+%$/.test(T.labels().pct), T.labels().pct);
  eq("anel na % do evento", T.run.pct, 54);
  eq("etapa em destaque pelo índice do servidor", T.items()[6].current, true);
  p.emit("progress", { pct: 61, label: "Baixar e compilar pacotes da AUR",
                       act: "Compilando whatsapp-linux-desktop-bin", idx: 6 });
  eq("atividade troca junto", T.labels().label,
     "Baixar e compilar pacotes da AUR · Compilando whatsapp-linux-desktop-bin");
  p.emit("progress", { pct: 85, label: "Desktop e serviços", act: "",
                       step: "stage.chroot.desktop", idx: 7 });
  eq("etapa nova limpa a atividade", T.labels().label, "Desktop e serviços");
  eq("índice da etapa segue o servidor", T.run.idx, 7);
  p.emit("progress", { pct: 40, label: "Desktop e serviços", act: "", idx: 7 });
  eq("anel ignora % atrasada", T.run.pct, 85);

  /* ----------------------------------------------------------------- */
  console.log("== lista de etapas ==");
  let items = T.items();
  eq("etapas anteriores marcadas como feitas", items.filter((i) => i.done).length, 7);
  eq("somente a atual em destaque", items.filter((i) => i.current).length, 1);
  // O anel anda dentro da etapa: com a % em 85 e a etapa da AUR (índice 6) em
  // curso, a lista não pode adiantar para o desktop só porque a % passou.
  T.run.idx = 6;
  T.renderSteps();
  items = T.items();
  eq("destaque pelo índice, não pela %", items[6].current, true);
  eq("etapa seguinte não acende", items[7].current, false);
  // Sem índice (plano antigo): cai para a comparação com a %.
  T.run.idx = -1;
  T.renderSteps();
  items = T.items();
  eq("fallback pela %", items[7].current, true);
  eq("fallback não destaca duas", items.filter((i) => i.current).length, 1);

  T.run.pct = 100;
  T.run.idx = 7;
  T.renderSteps();
  items = T.items();
  eq("em 100% as etapas até a atual ficam feitas", items.filter((i) => i.done).length, 8);
  check("em 100% nenhuma etapa fica em destaque", !items.some((i) => i.current));
  T.run.pct = 85;
  T.run.idx = 7;
  T.renderSteps();

  /* ----------------------------------------------------------------- */
  console.log("== plano de reserva (log sem NLSTEPS) ==");
  T.run.steps = [];
  T.run.stepSig = "";
  p.emit("state", st(PLAN_ONLINE, { mode: "offline", pct: 20, steps: [] }));
  items = T.items();
  eq("reserva offline", items.map((i) => i.pct), [0, 2, 4, 9, 13, 72, 85, 96, 99]);
  eq("reserva offline tem a etapa da cópia", items[4].text, "stage.copy.offline");
  check("monitor de download some no offline", T.labels().dlHidden === true);
  T.run.steps = [];
  T.run.stepSig = "";
  p.emit("state", st(PLAN_ONLINE, { mode: "online", pct: 20, steps: [] }));
  items = T.items();
  eq("reserva online", items.map((i) => i.pct), [0, 2, 4, 9, 13, 38, 54, 85, 96, 99]);
  eq("reserva online tem a etapa da AUR", items[6].text, "stage.chroot.aur");

  /* ----------------------------------------------------------------- */
  console.log("== stream fora do ar ==");
  p.emit("error", {});
  eq("queda mostra reconectando", T.labels().label, "web.reconnecting");
  p.emit("progress", { pct: 86, label: "Desktop e serviços", act: "Ativando o gerenciador de display", idx: 7 });
  p.emit("error", {});
  eq("rótulo de reconexão não é atropelado", T.labels().label, "web.reconnecting");
  p.emit("state", st(PLAN_ONLINE, { pct: 90, label: "Desktop e serviços", act: "", idx: 7 }));
  eq("rótulo volta quando o stream volta", T.labels().label, "Desktop e serviços");

  /* ----------------------------------------------------------------- */
  console.log("== log e cauda ao vivo ==");
  p.emit("tail", { line: "   Compiling umbriel-git v0.1.0" });
  eq("cauda mostra a última linha", T.labels().tail, "   Compiling umbriel-git v0.1.0");
  p.emit("log", { lines: ["a", "b"] });
  await sleep(60);
  eq("log recebe as linhas", T.labels().log, "a\nb");
  p.emit("log", { line: "c" });
  await sleep(60);
  eq("log aceita linha solta", T.labels().log, "a\nb\nc");

  /* ----------------------------------------------------------------- */
  console.log("== relógio ==");
  T.stopClock();

  /* ----------------------------------------------------------------- */
  /* Página nova: startInstall só roda uma vez por página (o app trava com
     installRequested para não disparar dois POSTs). */
  console.log("== nova instalação limpa o estado ==");
  const q = boot({});
  await sleep(60);
  const U = q.T;
  U.run.act = "Compilando umbriel-git";
  U.run.idx = 6;
  U.run.label = "Baixar e compilar pacotes da AUR";
  U.run.pct = 72;
  U.run.steps = PLAN_ONLINE.map(([pct, label]) => ({ pct, label }));
  U.run.stepSig = "x";
  U.run.lines = ["lixo antigo"];
  U.applyState(st(PLAN_ONLINE, { pct: 72, label: "Baixar e compilar pacotes da AUR",
                                 act: "Compilando umbriel-git", idx: 6 }));
  await U.startInstall();
  eq("atividade limpa", U.run.act, "");
  eq("índice limpo", U.run.idx, -1);
  eq("rótulo limpo", U.run.label, "");
  eq("anel volta a zero", U.run.pct, 0);
  eq("texto do anel volta a 0%", U.labels().pct, "0%");
  eq("lista de etapas limpa", U.run.steps.length, 0);
  eq("log antigo descartado", U.run.lines.length, 0);
  check("pedido de instalação foi feito",
        q.fetchLog.some(([u, m]) => u === "/api/install" && m === "POST"),
        JSON.stringify(q.fetchLog));
  await U.startInstall();
  eq("segundo startInstall é ignorado",
     q.fetchLog.filter(([u]) => u === "/api/install").length, 1);
  U.stopClock();

  console.log("");
  if (fails.length) {
    console.log("FALHAS: " + fails.length + " -> " + JSON.stringify(fails));
    process.exit(1);
  }
  console.log("todas as checagens passaram");
  process.exit(0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
