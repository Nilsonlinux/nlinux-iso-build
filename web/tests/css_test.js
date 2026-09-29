/* Valida o style.css do painel: sintaxe (css-tree) e as regras que o anel e
   a linha de etapa dependem.

     cd web/tests && npm install && node css_test.js

   O `npm install` é só uma vez: traz o css-tree. Sem node/npm, use
   `web/tests/run-tests.sh`, que pula esta suíte. */
"use strict";
const fs = require("fs");
const path = require("path");
const csstree = require("css-tree");

// web/tests/ -> web/ -> static/
const STATIC = path.join(__dirname, "..", "static");
const CSS = path.join(STATIC, "style.css");
const src = fs.readFileSync(CSS, "utf8");
const fails = [];
const check = (n, c, extra = "") => {
  if (c) console.log("  ok   " + n);
  else { console.log("  FAIL " + n + " -> " + extra); fails.push(n); }
};

const ast = csstree.parse(src, { positions: true, onParseError: (e) => {
  console.log("  FAIL css-tree: " + e.message + " (linha " + e.line + ")");
  fails.push("sintaxe do css");
} });
check("css-tree não acusou erro de sintaxe", fails.length === 0);

const rules = [];
csstree.walk(ast, { visit: "Rule", enter(node) { rules.push(node); } });
const sel = (r) => csstree.generate(r.prelude).replace(/\s+/g, "");
const findRule = (needle) => rules.find((r) => sel(r).includes(needle.replace(/\s+/g, "")));
const decls = new Map();
for (const r of rules) {
  const s = sel(r);
  r.block.children.forEach((c) => {
    if (c.type === "Declaration") decls.set(s + "{" + c.property, csstree.generate(c.value));
  });
}
const get = (s, prop) => decls.get(s.replace(/\s+/g, "") + "{" + prop);

/* A linha de etapa é a que mudou: nome longo + atividade. Precisa poder
   quebrar em duas linhas sem estourar a largura do painel. */
const label = findRule(".stage-label");
check("existe a regra .stage-label", !!label);
const lsel = ".stage-label";
const lprops = new Set();
label.block.children.forEach((c) => { if (c.type === "Declaration") lprops.add(c.property); });
for (const p of ["max-width", "line-height"]) {
  check(lsel + " tem " + p, lprops.has(p), [...lprops].join(", "));
}
check(".stage-label limita a largura", get(lsel, "max-width") === "34em", get(lsel, "max-width"));
check(".stage-label equilibra as linhas", get(lsel, "text-wrap") === "balance", get(lsel, "text-wrap"));
check(".stage-label não é monoespaçada", !get(lsel, "font-family") || !/mono/i.test(get(lsel, "font-family")),
      get(lsel, "font-family"));

/* O anel: o traço do progresso e o número no centro. */
const html = fs.readFileSync(path.join(STATIC, "index.html"), "utf8");
const js = fs.readFileSync(path.join(STATIC, "app.js"), "utf8");
check("o anel anima por stroke-dashoffset", !!get(".ring-fg", "transition"), get(".ring-fg", "transition"));
check("o número do anel tem tamanho", !!get("#ring-pct", "font-size"), get("#ring-pct", "font-size"));
check("raio do círculo é 88 no index.html", /id="ring-fg"[^>]*r="88"/.test(html));
check("app.js calcula a circunferência com o raio 88", /2 \* Math\.PI \* 88/.test(js));
check("a lista de etapas tem item", !!get(".stage-item", "display"));

/* As fitas do relógio: a altura tem de bater com o DIGIT_STEP do app.js. */
const digit = findRule(".digit");
const dsel = digit && sel(digit);
check("tem a regra do dígito", !!dsel);
const iRule = findRule(".digit > i");
const isel = iRule && sel(iRule);
check("tem a fita .digit > i", !!isel, isel);
const spanRule = findRule(".digit > i > span");
check("tem o digito .digit > i > span", !!spanRule);
const ssel = spanRule && sel(spanRule);
const lh = get(ssel, "line-height");
check("altura da fita = 1.2em (DIGIT_STEP do app.js)", lh === "1.2em", lh);
check("a fita esconde o resto dos dígitos", get(dsel, "overflow") === "hidden", get(dsel, "overflow"));
check("o dígito tem a altura da fita", get(dsel, "height") === "1.2em", get(dsel, "height"));
check("o app.js usa o mesmo passo", /const DIGIT_STEP = 1\.2;/.test(js));

console.log("");
if (fails.length) { console.log("FALHAS: " + fails.length + " -> " + JSON.stringify(fails)); process.exit(1); }
console.log("todas as checagens passaram");
