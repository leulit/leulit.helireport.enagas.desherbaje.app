// Helireport Desherbaje — Presentación "Flujo de información end-to-end"
// Audiencia mixta Enagas + contratista. PPTX vía pptxgenjs.
// Run: NODE_PATH=$(npm root -g) node build_flujo_deck.js

const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const FA = require("react-icons/fa");

// ─── Paleta Forest & Moss + colores reales de estado de la app ───────────────
const C = {
  forest: "2C5F2D",
  forestDark: "1B3A1C",
  moss: "97BC62",
  cream: "F5F5F5",
  card: "FFFFFF",
  ink: "2B2B2B",
  gray: "6B6B6B",
  line: "DDE3D8",
};
const ESTADO = {
  propuesta: "78909C",
  validada: "1976D2",
  contratista: "F45DEA",
  ejecucion: "F57C00",
  finalizada: "388E3C",
  cerrada: "546E7A",
};

const HEAD = "Georgia";
const BODY = "Calibri";
const W = 13.33, H = 7.5, M = 0.6;

// ─── Iconos react-icons → PNG base64 ─────────────────────────────────────────
async function icon(Comp, color = "FFFFFF", size = 256) {
  const svg = ReactDOMServer.renderToStaticMarkup(
    React.createElement(Comp, { color: "#" + color, size: String(size) })
  );
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + png.toString("base64");
}

const shadow = () => ({ type: "outer", color: "000000", blur: 7, offset: 3, angle: 135, opacity: 0.16 });

(async () => {
  const p = new pptxgen();
  p.layout = "LAYOUT_WIDE";
  p.author = "Leulit";
  p.title = "Helireport Desherbaje — Flujo de información";

  // Pre-rasterizar iconos
  const ic = {
    leaf: await icon(FA.FaLeaf, C.moss, 256),
    flow: await icon(FA.FaProjectDiagram, "FFFFFF"),
    tags: await icon(FA.FaTags, "FFFFFF"),
    life: await icon(FA.FaSyncAlt, "FFFFFF"),
    download: await icon(FA.FaCloudDownloadAlt, "FFFFFF"),
    map: await icon(FA.FaMapMarkedAlt, "FFFFFF"),
    cut: await icon(FA.FaCut, "FFFFFF"),
    loop: await icon(FA.FaExchangeAlt, "FFFFFF"),
    camera: await icon(FA.FaCamera, "FFFFFF"),
    sync: await icon(FA.FaCloud, "FFFFFF"),
    shield: await icon(FA.FaShieldAlt, "FFFFFF"),
    check: await icon(FA.FaCheckCircle, "FFFFFF"),
    decision: await icon(FA.FaQuestionCircle, C.moss, 256),
  };

  // ─── helpers ───────────────────────────────────────────────────────────────
  function contentBg(s) {
    s.background = { color: C.cream };
    s.addShape(p.shapes.RECTANGLE, { x: 0, y: 0, w: W, h: 0.14, fill: { color: C.forest } });
    s.addText("Helireport · Desherbaje", { x: M, y: H - 0.5, w: 6, h: 0.3, fontFace: BODY, fontSize: 9, color: C.gray });
    s.addText("Enagas · Módulo Desherbaje", { x: W - M - 4, y: H - 0.5, w: 4, h: 0.3, fontFace: BODY, fontSize: 9, color: C.gray, align: "right" });
  }
  function header(s, title, iconData, accent = C.forest) {
    s.addShape(p.shapes.OVAL, { x: M, y: 0.52, w: 0.74, h: 0.74, fill: { color: accent }, shadow: shadow() });
    s.addImage({ data: iconData, x: M + 0.17, y: 0.69, w: 0.4, h: 0.4 });
    s.addText(title, { x: M + 0.95, y: 0.5, w: W - 2 * M - 1, h: 0.8, fontFace: HEAD, fontSize: 30, bold: true, color: C.forest, valign: "middle", margin: 0 });
  }
  function chip(s, x, y, label, color, w = 1.8, fs = 13) {
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y, w, h: 0.42, fill: { color }, rectRadius: 0.21, shadow: shadow() });
    s.addText(label, { x, y, w, h: 0.42, fontFace: BODY, fontSize: fs, bold: true, color: "FFFFFF", align: "center", valign: "middle", margin: 0 });
  }
  function arrow(s, x, y, w = 0.55) {
    s.addText("➜", { x, y, w, h: 0.42, fontFace: BODY, fontSize: 18, bold: true, color: C.moss, align: "center", valign: "middle", margin: 0 });
  }
  function bullets(s, items, x, y, w, h, fs = 16) {
    s.addText(items.map((t, i) => ({ text: t, options: { bullet: { code: "2022", indent: 16 }, breakLine: true, paraSpaceAfter: 10 } })),
      { x, y, w, h, fontFace: BODY, fontSize: fs, color: C.ink, valign: "top" });
  }

  // ─── S1 Portada ──────────────────────────────────────────────────────────
  {
    const s = p.addSlide();
    s.background = { color: C.forestDark };
    s.addShape(p.shapes.RECTANGLE, { x: 0, y: 0, w: 0.22, h: H, fill: { color: C.moss } });
    s.addShape(p.shapes.OVAL, { x: M + 0.1, y: 1.5, w: 1.1, h: 1.1, fill: { color: C.forest } });
    s.addImage({ data: ic.leaf, x: M + 0.36, y: 1.76, w: 0.58, h: 0.58 });
    s.addText("Helireport · Desherbaje", { x: M, y: 2.85, w: 11.6, h: 1.0, fontFace: HEAD, fontSize: 46, bold: true, color: "FFFFFF", margin: 0 });
    s.addText("Flujo de información de principio a fin: de la oficina de Enagas al campo, y de vuelta",
      { x: M + 0.02, y: 3.95, w: 10.8, h: 0.8, fontFace: BODY, fontSize: 19, color: C.moss, margin: 0 });
    s.addText("Módulo Desherbaje — Enagas   ·   App móvil de campo + Web de gestión   ·   Junio 2026",
      { x: M + 0.02, y: 6.4, w: 11.8, h: 0.4, fontFace: BODY, fontSize: 12, color: "C8D6BE", margin: 0 });
  }

  // ─── S2 Dos mundos ─────────────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "Dos mundos, un solo flujo", ic.flow);
    const cy = 1.7, ch = 3.1, cw = 4.7;
    // Card WEB
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: cy, w: cw, h: ch, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: 0.12, shadow: shadow() });
    s.addShape(p.shapes.RECTANGLE, { x: M, y: cy, w: cw, h: 0.62, fill: { color: C.forest } });
    s.addText("WEB · Gestores de Enagas", { x: M, y: cy, w: cw, h: 0.62, fontFace: HEAD, fontSize: 16, bold: true, color: "FFFFFF", align: "center", valign: "middle", margin: 0 });
    bullets(s, ["Preparan y asignan el trabajo", "Validan los cambios propuestos", "Aprueban las zonas nuevas", "Cierran las zonas terminadas"], M + 0.3, cy + 0.85, cw - 0.6, ch - 1.0, 15);
    // Card MÓVIL
    const x2 = W - M - cw;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: x2, y: cy, w: cw, h: ch, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: 0.12, shadow: shadow() });
    s.addShape(p.shapes.RECTANGLE, { x: x2, y: cy, w: cw, h: 0.62, fill: { color: C.moss } });
    s.addText("MÓVIL · Operadores del contratista", { x: x2, y: cy, w: cw, h: 0.62, fontFace: HEAD, fontSize: 16, bold: true, color: "1B3A1C", align: "center", valign: "middle", margin: 0 });
    bullets(s, ["Verifican la zona en campo", "Ejecutan los trabajos", "Reportan fotos antes / después", "Proponen cambios y zonas nuevas"], x2 + 0.3, cy + 0.85, cw - 0.6, ch - 1.0, 15);
    // Sync chip centro
    const scx = M + cw, scw = x2 - (M + cw);
    s.addText("➜", { x: scx, y: cy + 1.0, w: scw, h: 0.5, fontSize: 24, bold: true, color: C.moss, align: "center", margin: 0 });
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: scx + 0.05, y: cy + 1.55, w: scw - 0.1, h: 0.7, fill: { color: C.forestDark }, rectRadius: 0.12, shadow: shadow() });
    s.addText("SINCRO-\nNIZACIÓN", { x: scx + 0.05, y: cy + 1.55, w: scw - 0.1, h: 0.7, fontFace: BODY, fontSize: 11, bold: true, color: "FFFFFF", align: "center", valign: "middle", margin: 0 });
    s.addText("⬅", { x: scx, y: cy + 2.4, w: scw, h: 0.5, fontSize: 24, bold: true, color: C.moss, align: "center", margin: 0 });
    // Banda inferior
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: 5.25, w: W - 2 * M, h: 1.15, fill: { color: "E8F0E2" }, line: { color: C.moss, width: 1.5 }, rectRadius: 0.1 });
    s.addText([
      { text: "La app móvil funciona SIN conexión. ", options: { bold: true, color: C.forest } },
      { text: "Internet solo sirve para sincronizar: descargar el trabajo al empezar y subir lo hecho al terminar.", options: { color: C.ink } },
    ], { x: M + 0.35, y: 5.25, w: W - 2 * M - 0.7, h: 1.15, fontFace: BODY, fontSize: 16, valign: "middle", margin: 0 });
  }

  // ─── S3 Los 6 estados ────────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "Los 6 estados: el idioma común", ic.tags);
    const rows = [
      ["Propuesta", ESTADO.propuesta, "Gestor Enagas", "Zona propuesta por Enagas, pendiente de revisar en campo."],
      ["Validada", ESTADO.validada, "Gestor Enagas", "Aprobada por Enagas. Lista para ejecutar."],
      ["Contratista", ESTADO.contratista, "Operario", "El operario propone un cambio o una zona nueva. Espera validación de Enagas."],
      ["En Ejecución", ESTADO.ejecucion, "Operario", "Trabajos en curso."],
      ["Finalizada", ESTADO.finalizada, "Operario", "Trabajos terminados."],
      ["Cerrada", ESTADO.cerrada, "Gestor Enagas", "Zona cerrada por Enagas."],
    ];
    let y = 1.62;
    const rh = 0.72, gap = 0.07;
    for (const [name, col, owner, desc] of rows) {
      s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y, w: W - 2 * M, h: rh, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: 0.06 });
      chip(s, M + 0.18, y + (rh - 0.42) / 2, name, col, 2.0, 13);
      s.addText(owner, { x: M + 2.35, y, w: 2.2, h: rh, fontFace: BODY, fontSize: 13, bold: true, color: owner === "Operario" ? C.forest : "1565C0", valign: "middle", margin: 0 });
      s.addText(desc, { x: M + 4.65, y, w: W - 2 * M - 4.85, h: rh, fontFace: BODY, fontSize: 13.5, color: C.ink, valign: "middle", margin: 0 });
      y += rh + gap;
    }
    s.addText("Son los mismos colores que el operario ve en las tarjetas de la app.", { x: M, y: y + 0.02, w: W - 2 * M, h: 0.3, fontFace: BODY, italic: true, fontSize: 12, color: C.gray, margin: 0 });
  }

  // ─── S4 Ciclo de vida — dos caminos + bucle ────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "El ciclo de vida de una zona", ic.life);

    const cw = 1.6, gap = 0.44, ch = 0.46;
    const colX = [];
    for (let i = 0; i < 6; i++) colX.push(M + i * (cw + gap));
    // 0 Propuesta · 1 Contratista · 2 Validada · 3 En Ejecución · 4 Finalizada · 5 Cerrada
    const divX = colX[3] - 0.22;
    const yR1 = 2.45, yR2 = 4.45;

    const owners = {
      Propuesta: ["Enagas", "1565C0"], Contratista: ["Operario", C.forest],
      Validada: ["Enagas", "1565C0"], Ejecucion: ["Operario", C.forest],
      Finalizada: ["Operario", C.forest], Cerrada: ["Enagas", "1565C0"],
    };
    function node(name, color, ownerKey, x, y) {
      const [oLbl, oCol] = owners[ownerKey];
      s.addText(oLbl, { x, y: y - 0.30, w: cw, h: 0.26, fontFace: BODY, fontSize: 9.5, bold: true, color: oCol, align: "center", margin: 0 });
      chip(s, x, y, name, color, cw, 11);
    }
    function inArrow(xRight, y) {
      s.addText("➜", { x: xRight, y, w: gap, h: ch, fontFace: BODY, fontSize: 16, bold: true, color: C.moss, align: "center", valign: "middle", margin: 0 });
    }
    // bucle En Ejecución ⇄ Finalizada (flecha de retorno punteada bajo los chips)
    function loopBack(y) {
      const cxE = colX[3] + cw / 2, cxF = colX[4] + cw / 2, ly = y + ch + 0.16;
      s.addShape(p.shapes.LINE, { x: cxE, y: y + ch, w: 0, h: 0.16, line: { color: ESTADO.ejecucion, width: 1.75 } });
      s.addShape(p.shapes.LINE, { x: cxF, y: y + ch, w: 0, h: 0.16, line: { color: ESTADO.ejecucion, width: 1.75 } });
      s.addShape(p.shapes.LINE, { x: cxE, y: ly, w: cxF - cxE, h: 0, line: { color: ESTADO.ejecucion, width: 1.75, beginArrowType: "triangle", dashType: "dash" } });
      s.addText("↺ se repite n veces", { x: colX[3] - 0.4, y: ly + 0.03, w: (colX[4] + cw) - colX[3] + 0.8, h: 0.26, fontFace: BODY, fontSize: 10, italic: true, color: "B45309", align: "center", margin: 0 });
    }

    // leyenda + cabeceras de grupo (arranque vs tramo común)
    s.addText([
      { text: "Azul = Enagas (web)", options: { color: "1565C0", bold: true } },
      { text: "   ·   ", options: { color: C.gray } },
      { text: "Verde = Operario (móvil)", options: { color: C.forest, bold: true } },
    ], { x: M, y: 1.42, w: 7, h: 0.26, fontFace: BODY, fontSize: 11, margin: 0 });
    s.addShape(p.shapes.LINE, { x: divX, y: 1.98, w: 0, h: 3.18, line: { color: C.moss, width: 1.25, dashType: "dash" } });
    s.addText("El arranque cambia según el caso", { x: M, y: 1.70, w: divX - M, h: 0.26, fontFace: BODY, fontSize: 10.5, italic: true, color: C.gray, align: "center", margin: 0 });
    s.addText("Tramo común: ejecutar → finalizar → cerrar", { x: divX, y: 1.70, w: (W - M) - divX, h: 0.26, fontFace: BODY, fontSize: 10.5, italic: true, bold: true, color: C.forest, align: "center", margin: 0 });

    // ── Ruta normal (casos 1 y 2): Propuesta ─────► En Ejecución ──────────────
    node("Propuesta", ESTADO.propuesta, "Propuesta", colX[0], yR1);
    s.addShape(p.shapes.LINE, { x: colX[0] + cw + 0.05, y: yR1 + ch / 2, w: colX[3] - (colX[0] + cw) - 0.1, h: 0, line: { color: C.moss, width: 2, endArrowType: "triangle" } });
    s.addText("Casos 1-2 · Enagas asigna la zona ya validada", { x: colX[0] + cw, y: yR1 - 0.30, w: divX - (colX[0] + cw) - 0.05, h: 0.26, fontFace: BODY, fontSize: 10, italic: true, color: C.gray, align: "center", margin: 0 });
    node("En Ejecución", ESTADO.ejecucion, "Ejecucion", colX[3], yR1);
    inArrow(colX[3] + cw, yR1);
    node("Finalizada", ESTADO.finalizada, "Finalizada", colX[4], yR1);
    inArrow(colX[4] + cw, yR1);
    node("Cerrada", ESTADO.cerrada, "Cerrada", colX[5], yR1);
    loopBack(yR1);

    // ── Caso 3 (el operario propone cambio / zona nueva): + Contratista, Validada
    node("Propuesta", ESTADO.propuesta, "Propuesta", colX[0], yR2);
    inArrow(colX[0] + cw, yR2);
    node("Contratista", ESTADO.contratista, "Contratista", colX[1], yR2);
    inArrow(colX[1] + cw, yR2);
    node("Validada", ESTADO.validada, "Validada", colX[2], yR2);
    inArrow(colX[2] + cw, yR2);
    node("En Ejecución", ESTADO.ejecucion, "Ejecucion", colX[3], yR2);
    inArrow(colX[3] + cw, yR2);
    node("Finalizada", ESTADO.finalizada, "Finalizada", colX[4], yR2);
    inArrow(colX[4] + cw, yR2);
    node("Cerrada", ESTADO.cerrada, "Cerrada", colX[5], yR2);
    s.addText("Caso 3 · el operario propone; Enagas valida antes de ejecutar", { x: colX[0], y: yR2 + ch + 0.06, w: (colX[2] + cw) - colX[0], h: 0.26, fontFace: BODY, fontSize: 10, italic: true, color: "A21CAF", align: "center", margin: 0 });
    loopBack(yR2);

    // ── Callout ──
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: 5.55, w: W - 2 * M, h: 1.0, fill: { color: "E8F0E2" }, line: { color: C.moss, width: 1.5 }, rectRadius: 0.1 });
    s.addText([
      { text: "Lo único que cambia es el arranque: ", options: { bold: true, color: C.forest } },
      { text: "si el operario propone algo, la zona pasa por Contratista → Validada; si no, Enagas la asigna ya lista. El bucle ", options: { color: C.ink } },
      { text: "En Ejecución ⇄ Finalizada", options: { bold: true, color: "B45309" } },
      { text: " se repite tantas veces como haga falta antes de que Enagas cierre la zona.", options: { color: C.ink } },
    ], { x: M + 0.35, y: 5.55, w: W - 2 * M - 0.7, h: 1.0, fontFace: BODY, fontSize: 14.5, valign: "middle", margin: 0 });
  }

  // ─── S5 Punto 1 descarga ─────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "1 · Cómo llega el trabajo al móvil", ic.download, C.forest);
    bullets(s, [
      "El gestor de Enagas crea y asigna los segmentos en la web (estado Propuesta o Validada).",
      "El operario, en la pantalla “Sincronización”, pulsa “Preparar trabajo de campo” / Descargar.",
      "Se descargan: Segmentos asignados, Trazas de gasoductos, Puntos kilométricos y Datos de usuario.",
      "Se hace CON conexión, antes de salir. A partir de ahí, todo vive en el móvil y se trabaja sin red.",
    ], M, 1.85, W - 2 * M, 4.0, 17);
    chip(s, M, 5.7, "Propuesta", ESTADO.propuesta, 1.7, 12);
    chip(s, M + 1.95, 5.7, "Validada", ESTADO.validada, 1.7, 12);
    s.addText("← estados con los que nacen los segmentos en la web", { x: M + 3.9, y: 5.7, w: 7, h: 0.42, fontFace: BODY, italic: true, fontSize: 12, color: C.gray, valign: "middle", margin: 0 });
  }

  // ─── S6 Punto 2 verificar + proponer cambios ───────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "2 · Verificar y proponer cambios", ic.map, C.forest);
    bullets(s, [
      "El operario comprueba sobre el mapa que la zona indicada es correcta.",
      "Si la zona es más grande, más pequeña o está mal ubicada: usa “Editar extremos” para ajustar la geometría y edita la descripción / el tipo de actividad.",
      "Cambia el estado a “Contratista” → al sincronizar, Enagas ve la propuesta y la valida (o la devuelve).",
    ], M, 1.8, W - 2 * M, 2.9, 16.5);
    // aviso
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: 5.15, w: W - 2 * M, h: 1.25, fill: { color: "FFF3E0" }, line: { color: ESTADO.ejecucion, width: 1.5 }, rectRadius: 0.1 });
    s.addText([
      { text: "⚠  Caso “no hace falta actuar aquí”: ", options: { bold: true, color: "B45309" } },
      { text: "hoy se comunica por el chat de Mensajes + descripción, dejando la zona en “Contratista”. No existe todavía un estado “No requiere actuación” — decisión abierta con Enagas.", options: { color: C.ink } },
    ], { x: M + 0.35, y: 5.15, w: W - 2 * M - 0.7, h: 1.25, fontFace: BODY, fontSize: 14.5, valign: "middle", margin: 0 });
  }

  // ─── S7 Punto 3 zona nueva ─────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "3 · Proponer una zona nueva", ic.cut, C.forest);
    bullets(s, [
      "En el Mapa global, el operario activa el modo “Líneas de corte”.",
      "Con dos líneas corta la traza del gasoducto y extrae uno o varios segmentos nuevos.",
      "Rellena descripción y tipo de actividad. El nuevo segmento nace en estado “Contratista”.",
      "Al sincronizar, Enagas recibe la zona nueva y la valida.",
    ], M, 1.85, W - 2 * M, 3.6, 17);
    chip(s, M, 5.75, "Contratista", ESTADO.contratista, 2.0, 13);
    s.addText("← toda zona propuesta desde la app nace aquí, a la espera de validación de Enagas", { x: M + 2.2, y: 5.75, w: 9, h: 0.42, fontFace: BODY, italic: true, fontSize: 12, color: C.gray, valign: "middle", margin: 0 });
  }

  // ─── S8 Punto 4 bucle aprobación ────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "4 · El bucle de aprobación", ic.loop, C.forest);
    const y = 2.5;
    chip(s, M + 0.2, y, "Contratista", ESTADO.contratista, 2.3, 14);
    s.addText("el operario propone", { x: M + 0.2, y: y - 0.4, w: 2.3, h: 0.3, fontFace: BODY, fontSize: 11, bold: true, color: C.forest, align: "center", margin: 0 });
    arrow(s, M + 2.7, y, 0.7);
    s.addText("sincroniza", { x: M + 2.6, y: y + 0.45, w: 0.9, h: 0.3, fontFace: BODY, fontSize: 10, italic: true, color: C.gray, align: "center", margin: 0 });
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M + 3.55, y, w: 2.5, h: 0.42, fill: { color: C.forestDark }, rectRadius: 0.1, shadow: shadow() });
    s.addText("Enagas revisa", { x: M + 3.55, y, w: 2.5, h: 0.42, fontFace: BODY, fontSize: 13, bold: true, color: "FFFFFF", align: "center", valign: "middle", margin: 0 });
    arrow(s, M + 6.25, y, 0.7);
    chip(s, M + 7.1, y, "Validada", ESTADO.validada, 2.3, 14);
    s.addText("Enagas aprueba", { x: M + 7.1, y: y - 0.4, w: 2.3, h: 0.3, fontFace: BODY, fontSize: 11, bold: true, color: "1565C0", align: "center", margin: 0 });
    // return arrow
    s.addText("⟲ si hay que ajustar, Enagas la devuelve (mensaje / vuelve a Propuesta)", { x: M + 3.55, y: y + 0.95, w: 6, h: 0.4, fontFace: BODY, fontSize: 12, italic: true, color: C.gray, margin: 0 });
    // mensaje
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: 5.3, w: W - 2 * M, h: 1.1, fill: { color: "FCE4F9" }, line: { color: ESTADO.contratista, width: 1.5 }, rectRadius: 0.1 });
    s.addText([
      { text: "Mientras esté en “Contratista” (rosa) = pendiente de que Enagas lo valide. ", options: { bold: true, color: "A21CAF" } },
      { text: "Nada se da por aprobado hasta que Enagas lo pasa a “Validada”.", options: { color: C.ink } },
    ], { x: M + 0.35, y: 5.3, w: W - 2 * M - 0.7, h: 1.1, fontFace: BODY, fontSize: 16, valign: "middle", margin: 0 });
  }

  // ─── S9 Punto 5 fotos ──────────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "5 · Fotos antes y después", ic.camera, C.forest);
    bullets(s, [
      "En el detalle del segmento, pestañas “Antes” y “Después”.",
      "Cámara (foto nueva) o Galería (foto existente). Se geoposicionan automáticamente con el GPS.",
      "Se guardan en el móvil y suben al servidor al sincronizar.",
      "Buena práctica: foto “antes” antes de tocar nada; foto “después” al terminar; encuadre que permita reconocer la zona.",
    ], M, 1.95, W - 2 * M, 4.3, 17);
  }

  // ─── S10 Sincronización ──────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "Cómo viaja la información", ic.sync);
    bullets(s, [
      "Todo se guarda primero en el móvil: la app funciona aunque no haya cobertura.",
      "Solo 2 momentos necesitan red: DESCARGAR al empezar la jornada · SUBIR al terminarla.",
      "El badge superior indica el estado: Offline · Sincronizando · X pendientes · Sincronizado.",
    ], M, 1.85, W - 2 * M, 2.9, 17);
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y: 5.2, w: W - 2 * M, h: 1.05, fill: { color: "E8F0E2" }, line: { color: C.moss, width: 1.5 }, rectRadius: 0.1 });
    s.addText([
      { text: "Pendientes a 0 = jornada cerrada. ", options: { bold: true, color: C.forest } },
      { text: "Enagas ya tiene todo lo del operario.", options: { color: C.ink } },
    ], { x: M + 0.35, y: 5.2, w: W - 2 * M - 0.7, h: 1.05, fontFace: BODY, fontSize: 17, valign: "middle", margin: 0 });
  }

  // ─── S11 Trazabilidad ──────────────────────────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "Trazabilidad y control para Enagas", ic.shield);
    bullets(s, [
      "Cada cambio queda registrado: quién, cuándo, con foto y posición GPS.",
      "Aprobación explícita: nada entra en la planificación sin que un gestor de Enagas lo valide.",
      "Ruta GPS del operario (mientras está en el mapa) → mejora la planificación del año siguiente.",
      "Chat por segmento (Mensajes) → justificación documentada de cada propuesta.",
    ], M, 1.95, W - 2 * M, 4.3, 17);
  }

  // ─── S12 Qué debe tener claro el operario ───────────────────────────────────
  {
    const s = p.addSlide();
    contentBg(s);
    header(s, "Qué debe tener claro el operario", ic.check);
    const cards = [
      ["1", "Verifica antes de ejecutar", "La zona de Enagas puede no coincidir con el terreno real."],
      ["2", "Proponer = estado “Contratista”", "Tú propones, Enagas aprueba. No está hecho hasta que Enagas valida."],
      ["3", "Fotos siempre", "Una antes y una después de cada actuación."],
      ["4", "Sincroniza al empezar y al terminar", "Descargar al salir · subir hasta 0 pendientes al volver."],
    ];
    const cw = 2.78, gap = 0.3, y = 1.9, ch = 3.65;
    let x = (W - (4 * cw + 3 * gap)) / 2;
    for (const [n, t, d] of cards) {
      s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: ch, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: 0.1, shadow: shadow() });
      s.addShape(p.shapes.RECTANGLE, { x, y, w: cw, h: 0.16, fill: { color: C.moss } });
      s.addShape(p.shapes.OVAL, { x: x + cw / 2 - 0.45, y: y + 0.45, w: 0.9, h: 0.9, fill: { color: C.forest } });
      s.addText(n, { x: x + cw / 2 - 0.45, y: y + 0.45, w: 0.9, h: 0.9, fontFace: HEAD, fontSize: 30, bold: true, color: "FFFFFF", align: "center", valign: "middle", margin: 0 });
      s.addText(t, { x: x + 0.2, y: y + 1.55, w: cw - 0.4, h: 0.95, fontFace: HEAD, fontSize: 15, bold: true, color: C.forest, align: "center", valign: "top", margin: 0 });
      s.addText(d, { x: x + 0.2, y: y + 2.5, w: cw - 0.4, h: 1.05, fontFace: BODY, fontSize: 12.5, color: C.ink, align: "center", valign: "top", margin: 0 });
      x += cw + gap;
    }
  }

  // ─── S13 Cierre / decisión abierta ──────────────────────────────────────────
  {
    const s = p.addSlide();
    s.background = { color: C.forestDark };
    s.addShape(p.shapes.RECTANGLE, { x: 0, y: 0, w: 0.22, h: H, fill: { color: ESTADO.contratista } });
    s.addShape(p.shapes.OVAL, { x: M + 0.1, y: 1.2, w: 1.0, h: 1.0, fill: { color: C.forest } });
    s.addImage({ data: ic.decision, x: M + 0.33, y: 1.43, w: 0.54, h: 0.54 });
    s.addText("Una decisión que cerrar con Enagas", { x: M, y: 2.5, w: 11.8, h: 0.9, fontFace: HEAD, fontSize: 34, bold: true, color: "FFFFFF", margin: 0 });
    s.addText([
      { text: "¿Añadimos un estado “No requiere actuación / Descartada” ", options: { bold: true, color: C.moss } },
      { text: "para las zonas donde el operario determina en campo que no hay que actuar? Hoy se gestiona por mensaje + estado “Contratista”.", options: { color: "EAF1E4" } },
    ], { x: M + 0.02, y: 3.6, w: 11.4, h: 1.6, fontFace: BODY, fontSize: 19, margin: 0 });
    s.addText("Helireport · Desherbaje — Leulit   ·   Junio 2026", { x: M, y: 6.5, w: 11.8, h: 0.4, fontFace: BODY, fontSize: 12, color: "C8D6BE", margin: 0 });
  }

  await p.writeFile({ fileName: "docs/formacion/presentacion_flujo_informacion.pptx" });
  console.log("OK: docs/formacion/presentacion_flujo_informacion.pptx");
})();
