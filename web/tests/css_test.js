// SPDX-License-Identifier: GPL-3.0-or-later
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

/* As fitas do relógio: é aqui que um dígito saía alguns milímetros da linha
   dos outros. A janela do dígito e o passo do translateY têm de ser a MESMA
   medida — e em `rem`, não em `em`: o navegador resolve `em` por dois caminhos
   (o height da caixa passa pelo font-size arredondado, o transform não), a fita
   anda um pouco diferente da janela e, como o erro é por dígito, cada um sai um
   pouco diferente do vizinho. Medido no Firefox: caixa 32px com passo de
   32.625px deixava os dígitos em 372, 370, 369, 368... px. */
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
const alturaJanela = get(dsel, "height");
const alturaDigito = get(ssel, "height");
const lhFita = get(isel, "line-height");
const lhDigito = get(dsel, "line-height");

check("o número da fita tem altura = a janela do dígito",
      alturaDigito && alturaDigito === alturaJanela, alturaDigito + " vs " + alturaJanela);
check("altura da fita em rem (não em em, que o navegador resolve diferente)",
      /(?:^|\s)\d*\.?\d+rem$/.test(String(alturaJanela))
        && !/(?:^|\s)\d*\.?\d+em(?:\s|;|$)/.test(String(alturaJanela)),
      alturaJanela);
check("a fita e o número usam o mesmo line-height", lh === lhFita, lh + " vs " + lhFita);
check("a janela do dígito usa o mesmo line-height", lh === lhDigito, lh + " vs " + lhDigito);
check("a fita esconde o resto dos dígitos", get(dsel, "overflow") === "hidden", get(dsel, "overflow"));

/* O app.js tem de andar o mesmo número de rem que a altura da janela. */
const passoJs = /const DIGIT_STEP = (\d+(?:\.\d+)?);/.exec(js);
check("o app.js declara o passo da fita", !!passoJs, js.match(/DIGIT_STEP[^;]*;/));
if (passoJs) {
  const rem = parseFloat(String(alturaJanela));
  check("o app.js usa o mesmo passo em rem da janela (" + rem + "rem)",
        Math.abs(parseFloat(passoJs[1]) - rem) < 1e-9, passoJs[1]);
  check("o transform sai em rem", /DIGIT_STEP\)\.toFixed\(\d+\) \+ "rem\)"/.test(js),
        (js.match(/strip\.style\.transform = [^\n]*/g) || []).join(" | "));
}

/* A curva da fita não pode ultrapassar o destino: o overshoot da curva antiga
   (cubic-bezier(.34, 1.3, .5, 1)) passava 3% do alvo — ~9px na virada 9 -> 0,
   que anda 10 dígitos de uma vez. */
const trans = get(isel, "transition") || "";
const bez = /cubic-bezier\(([^)]*)\)/.exec(trans);
check("a fita tem curva de transição", !!bez, trans);
if (bez) {
  const ys = bez[1].split(",").map((n) => parseFloat(n.trim())).filter((_, i) => i % 2 === 1);
  check("a curva é monôtona (nenhum ponto de controle passa de 1)",
        ys.every((y) => y <= 1), bez[1]);
}

/* Os dois-pontos dividem a caixa de linha dos dígitos: senão ficam numa linha
   diferente dos números. */
const relSel = ".clock-digits";
check("o relógio fixa a caixa de linha dos dois-pontos",
      get(relSel, "line-height") === alturaJanela,
      get(relSel, "line-height") + " vs " + alturaJanela);

/* A caixinha azul que ficava sobre o log (a "cauda" com a última linha do
   install) foi removida: a atividade de agora já está na linha da etapa, no
   anel e no log. Nenhum resquício dela pode voltar. */
check("a regra .live-tail não existe mais", !findRule(".live-tail"));
check("o elemento #live-tail saiu do HTML", !/id="live-tail"/.test(html));
check("nada mais escreve na cauda", !/live-tail/.test(js));

/* Monitor do download: rótulo + valor, um par por medida, na mesma linha. */
const cellSel = ".dl-cell";
check("existe a regra .dl-cell", !!findRule(cellSel));
check("cada medida é um par rótulo/valor", get(cellSel, "display") === "inline-flex",
      get(cellSel, "display"));
check("o par alinha pela linha de base", get(cellSel, "align-items") === "baseline",
      get(cellSel, "align-items"));
check("os valores ficam em monoespaçada",
      !!get(".dl-values", "font-family") && /mono/i.test(get(".dl-values", "font-family")),
      get(".dl-values", "font-family"));
check("os valores não quebram de linha", get(".dl-val", "white-space") === "nowrap",
      get(".dl-val", "white-space"));
for (const [rot, val] of [["dl-size-label", "dl-total"], ["dl-got-label", "dl-got"],
                          ["dl-avg-label", "dl-rate"]]) {
  check(`a medida ${val} tem o rótulo ${rot}`,
        new RegExp(`id="${rot}"[\\s\\S]{0,80}id="${val}"`).test(html));
}

console.log("");
if (fails.length) { console.log("FALHAS: " + fails.length + " -> " + JSON.stringify(fails)); process.exit(1); }
console.log("todas as checagens passaram");
