import { RUNES, runeById } from "./rune-definitions.js";
import { RELICS, relicById } from "./relic-definitions.js";
import { axialToPoint, createHexDisk, hexLine, keyOf, polygonPoints } from "./hex-grid.js";
import { RuneEngine } from "./rune-engine.js";
import { CircleStorage } from "./storage.js";

const NS = "http://www.w3.org/2000/svg";
const cells = createHexDisk(4);
const engine = new RuneEngine(RUNES, cells, RELICS);
const elements = {
  board: document.querySelector("#hex-board"), activeList: document.querySelector("#active-list"),
  book: document.querySelector("#rune-book-list"), toast: document.querySelector("#board-toast"),
  drawState: document.querySelector("#draw-state"), commit: document.querySelector("#commit-button"),
  undo: document.querySelector("#undo-button"), cancel: document.querySelector("#cancel-button"),
  clear: document.querySelector("#clear-button"), save: document.querySelector("#save-button"),
  saveStatus: document.querySelector("#save-status"), dialog: document.querySelector("#clear-dialog"),
  confirmClear: document.querySelector("#confirm-clear"), bookCount: document.querySelector("#book-count"),
  relicList: document.querySelector("#relic-list"),
  handdrawToggle: document.querySelector("#handdraw-toggle"), handdrawStatus: document.querySelector("#handdraw-status"),
  helpButton: document.querySelector("#help-button"), helpDialog: document.querySelector("#help-dialog"), closeHelp: document.querySelector("#close-help"),
};

let isDrawing = false;
let selectedRuneId = RUNES[0].id;
let dirty = false;
let toastTimer;
let relicGhost = null;
let activeRelicId = "";
let freehandMode = false;
let freehandPoints = [];
let freehandCells = [];
let freehandBlocked = false;

const svg = (tag, attributes = {}) => {
  const node = document.createElementNS(NS, tag);
  Object.entries(attributes).forEach(([name, value]) => node.setAttribute(name, value));
  return node;
};

function setToast(message, tone = "neutral") {
  clearTimeout(toastTimer);
  elements.toast.textContent = message;
  elements.toast.dataset.tone = tone;
  elements.toast.classList.add("is-visible");
  toastTimer = setTimeout(() => elements.toast.classList.remove("is-visible"), 3600);
}

function markDirty() {
  dirty = true;
  elements.saveStatus.textContent = "本机草稿 · 有未保存修改";
  elements.saveStatus.classList.add("is-dirty");
}

function renderBoard() {
  elements.board.replaceChildren();
  const defs = svg("defs");
  const glow = svg("filter", { id: "rune-glow", x: "-40%", y: "-40%", width: "180%", height: "180%" });
  glow.append(svg("feGaussianBlur", { stdDeviation: "5", result: "blur" }), svg("feMerge"));
  glow.lastChild.append(svg("feMergeNode", { in: "blur" }), svg("feMergeNode", { in: "SourceGraphic" }));
  defs.append(glow);
  elements.board.append(defs);

  const draftKeys = new Set(engine.draft.map(keyOf));
  cells.forEach((cell) => {
    const key = keyOf(cell);
    const owner = engine.occupied.get(key);
    const placed = owner && engine.placed.find((item) => item.uid === owner);
    const placedRelic = owner && engine.placedRelics.find((item) => item.uid === owner);
    const rune = placed && runeById(placed.runeId);
    const relic = placedRelic && relicById(placedRelic.relicId);
    const polygon = svg("polygon", {
      points: polygonPoints(cell, 32, [380, 325]).map((point) => point.join(",")).join(" "),
      class: `hex-cell${placed || placedRelic ? " is-occupied" : ""}${placedRelic ? " is-relic" : ""}${draftKeys.has(key) ? " is-draft" : ""}${placed && !placed.enabled ? " is-disabled" : ""}`,
      "data-cell": key,
      "data-owner": owner || "",
      style: rune || relic ? `--rune-color:${(rune || relic).color}` : "",
      tabindex: "0",
      role: "button",
      "aria-label": `${key} 蜂窝${placed ? `，属于${rune.name}符文` : placedRelic ? `，属于${relic.name}奇物` : "，空闲"}`,
    });
    elements.board.append(polygon);
  });

  engine.placed.forEach((placed) => drawPath(placed.cells, runeById(placed.runeId).color, placed.enabled ? "placed" : "disabled", placed.uid));
  engine.placedRelics.forEach((placed) => drawRelic(placed));
  if (relicGhost) drawRelicGhost(relicGhost);
  if (engine.draft.length) drawPath(engine.draft, "#e8b45c", "draft");
  if (freehandPoints.length > 1) drawFreehandStroke();
}

function drawFreehandStroke() {
  const points = freehandPoints.map((point) => point.join(",")).join(" ");
  elements.board.append(svg("polyline", { points, class: `freehand-stroke freehand-stroke--glow${freehandBlocked ? " is-blocked" : ""}` }));
  elements.board.append(svg("polyline", { points, class: `freehand-stroke${freehandBlocked ? " is-blocked" : ""}` }));
}

function drawRelic(placed) {
  const relic = relicById(placed.relicId);
  const points = placed.cells.map((cell) => axialToPoint(cell, 34, [380, 325]));
  points.forEach(([x, y]) => elements.board.append(svg("path", {
    d: `M ${x - 10} ${y} L ${x} ${y - 10} L ${x + 10} ${y} L ${x} ${y + 10} Z`,
    class: "relic-node", style: `--rune-color:${relic.color}`, "data-owner": placed.uid,
  })));
}

function drawRelicGhost(ghost) {
  ghost.cells.forEach((cell) => {
    const [x, y] = axialToPoint(cell, 34, [380, 325]);
    elements.board.append(svg("circle", { cx: x, cy: y, r: 22, class: `relic-ghost${ghost.valid ? "" : " is-invalid"}` }));
  });
}

function drawPath(path, color, kind, uid = "") {
  const points = path.map((cell) => axialToPoint(cell, 34, [380, 325]));
  const polyline = svg("polyline", {
    points: points.map((point) => point.join(",")).join(" "),
    class: `rune-path rune-path--${kind}`,
    style: `--rune-color:${color}`,
    "data-owner": uid,
    filter: kind === "disabled" ? "" : "url(#rune-glow)",
  });
  elements.board.append(polyline);
  points.forEach(([x, y], index) => elements.board.append(svg("circle", {
    cx: x, cy: y, r: index === 0 ? 6 : 4.5,
    class: `rune-node rune-node--${kind}`,
    style: `--rune-color:${color}`,
    "data-owner": uid,
  })));
}

function previewSvg(rune) {
  const positions = rune.cells.map((cell) => axialToPoint(cell, 11, [0, 0]));
  const xs = positions.map(([x]) => x); const ys = positions.map(([, y]) => y);
  const center = [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...ys) + Math.max(...ys)) / 2];
  const points = positions.map(([x, y]) => [50 + x - center[0], 43 + y - center[1]]);
  return `<svg viewBox="0 0 100 86" aria-hidden="true"><polyline points="${points.map((point) => point.join(",")).join(" ")}" style="--rune-color:${rune.color}"/>${points.map(([x, y]) => `<circle cx="${x}" cy="${y}" r="3.5"/>`).join("")}</svg>`;
}

function renderBook() {
  elements.bookCount.textContent = String(RUNES.length).padStart(2, "0");
  elements.book.innerHTML = RUNES.map((rune) => `
    <article class="rune-card${selectedRuneId === rune.id ? " is-selected" : ""}" style="--rune-color:${rune.color}" data-rune="${rune.id}">
      <button class="rune-select" type="button" aria-label="查看${rune.name}符文"><span class="rune-preview">${previewSvg(rune)}</span><span class="rune-copy"><span class="rune-title"><strong>${rune.name}</strong><em>${rune.subtitle}</em></span><span>${rune.effect}</span><small>${rune.cells.length} 格 · 可旋转 / 镜像</small></span></button>
      <p class="rune-detail">${rune.detail}</p>
    </article>`).join("");
}

function renderActive() {
  if (!engine.placed.length) {
    elements.activeList.innerHTML = '<span class="empty-active">尚无符文</span>';
    return;
  }
  elements.activeList.innerHTML = engine.placed.map((item) => {
    const rune = runeById(item.runeId);
    return `<label class="active-chip${item.enabled ? "" : " is-off"}" style="--rune-color:${rune.color}"><input type="checkbox" data-toggle="${item.uid}" ${item.enabled ? "checked" : ""}/><span class="check-mark"></span><span><strong>${rune.name}</strong><small>${item.enabled ? "生效中" : "已停用"}</small></span><button type="button" data-remove="${item.uid}" aria-label="移除${rune.name}符文">×</button></label>`;
  }).join("");
}

function renderRelics() {
  elements.relicList.innerHTML = RELICS.map((relic) => {
    const placed = engine.placedRelics.find((item) => item.relicId === relic.id);
    return `<article class="relic-card${placed ? " is-placed" : ""}" style="--relic-color:${relic.color}" draggable="false" data-relic="${relic.id}">
      <span class="relic-grip" aria-hidden="true">⠿</span>
      <span class="relic-mini">${previewSvg(relic)}</span>
      <span class="relic-copy"><span><strong>${relic.name}</strong><em>${relic.subtitle}</em></span><small>${relic.effect}</small><b>${placed ? "已置入阵面" : `${relic.cells.length} 格 · 拖入阵面`}</b></span>
      ${placed ? `<button type="button" data-recall="${placed.uid}">回收</button>` : ""}
    </article>`;
  }).join("");
}

function renderControls() {
  const hasDraft = engine.draft.length > 0;
  elements.commit.disabled = !hasDraft;
  elements.undo.disabled = !hasDraft;
  elements.cancel.disabled = !hasDraft;
  const match = engine.recognize();
  elements.drawState.textContent = hasDraft ? (match ? `已识别 · ${match.name}` : `描画中 · ${engine.draft.length} 格`) : "等待落笔";
  elements.drawState.classList.toggle("is-match", Boolean(match));
}

function render() {
  renderBoard(); renderActive(); renderBook(); renderRelics(); renderControls();
}

function cellFromTarget(target) {
  const raw = target.closest?.("[data-cell]")?.dataset.cell;
  return raw ? raw.split(",").map(Number) : null;
}

function beginDraw(cell) {
  const owner = engine.occupied.get(keyOf(cell));
  if (owner) {
    const relic = engine.placedRelics.find((item) => item.uid === owner);
    if (relic) {
      setToast(`「${relicById(relic.relicId).name}」是固定奇物，可从左侧回收`, "neutral");
      return;
    }
    const item = engine.toggle(owner);
    markDirty(); render();
    setToast(`${runeById(item.runeId).name}已${item.enabled ? "重新勾选" : "取消勾选"}`, item.enabled ? "success" : "neutral");
    return;
  }
  // Support both click-by-click drafting and click-drag drawing. A non-adjacent
  // click intentionally starts a fresh stroke, so the interaction never traps
  // the player in an invalid partial path.
  const extended = engine.draft.length ? engine.extend(cell) : null;
  const result = extended?.ok ? extended : engine.begin(cell);
  if (result.ok) { isDrawing = true; markDirty(); render(); }
}

elements.board.addEventListener("pointerdown", (event) => {
  const cell = cellFromTarget(event.target);
  if (!cell) return;
  event.preventDefault();
  elements.board.setPointerCapture(event.pointerId);
  if (freehandMode) {
    if (!engine.canUse(cell)) { setToast("落笔位置已被占用", "error"); return; }
    isDrawing = true;
    freehandBlocked = false;
    freehandCells = [cell];
    freehandPoints = [jitterPoint(pointerToSvg(event), 0)];
    renderBoard();
    return;
  }
  beginDraw(cell);
});
elements.board.addEventListener("pointermove", (event) => {
  if (!isDrawing) return;
  if (freehandMode) {
    const raw = pointerToSvg(event);
    const previous = freehandPoints.at(-1);
    if (!previous || Math.hypot(previous[0] - raw[0], previous[1] - raw[1]) > 2.5) {
      freehandPoints.push(jitterPoint(raw, freehandPoints.length));
    }
    const cell = nearestCellFromPointer(event);
    const lastCell = freehandCells.at(-1);
    if (cell && keyOf(cell) !== keyOf(lastCell)) {
      for (const crossed of hexLine(lastCell, cell).slice(1)) {
        if (freehandCells.some((used) => keyOf(used) === keyOf(crossed)) || !engine.canUse(crossed)) {
          freehandBlocked = true;
          break;
        }
        freehandCells.push(crossed);
      }
    }
    renderBoard();
    return;
  }
  const target = document.elementFromPoint(event.clientX, event.clientY);
  const cell = cellFromTarget(target);
  if (cell && engine.extend(cell).ok) render();
});
elements.board.addEventListener("pointerup", () => {
  if (freehandMode && isDrawing) settleFreehandStroke();
  isDrawing = false;
});
elements.board.addEventListener("pointercancel", () => {
  isDrawing = false; freehandPoints = []; freehandCells = []; freehandBlocked = false; renderBoard();
});

function pointerToSvg(event) {
  // Use the SVG's actual screen transform instead of scaling against its CSS
  // box. This accounts for viewBox letterboxing, responsive layout and CSS
  // transforms, which otherwise make the brush drift away from the pointer.
  const matrix = elements.board.getScreenCTM();
  if (!matrix) return [0, 0];
  const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse());
  return [point.x, point.y];
}

function jitterPoint([x, y], index) {
  const amplitude = 3.2;
  return [x + Math.sin(index * 2.17) * amplitude + (Math.random() - .5) * 2, y + Math.cos(index * 1.73) * amplitude + (Math.random() - .5) * 2];
}

function settleFreehandStroke() {
  engine.cancel();
  if (freehandCells.length) {
    engine.begin(freehandCells[0]);
    freehandCells.slice(1).forEach((cell) => engine.extend(cell));
  }
  const wasBlocked = freehandBlocked;
  freehandPoints = []; freehandCells = []; freehandBlocked = false;
  if (engine.draft.length) markDirty();
  render();
  const matched = engine.recognize();
  if (matched) setToast(`笔触已吸附 · 识别为「${matched.name}」`, "success");
  else if (wasBlocked) setToast("笔触碰到已占用蜂窝，已在冲突位置截断", "error");
  else setToast("笔触已吸附为蜂窝连线，可撤回或继续修正");
}

elements.commit.addEventListener("click", () => {
  const result = engine.commit();
  if (!result.ok) { setToast("图形未被识别，请对照右侧符文书。顺序也要连续。", "error"); return; }
  selectedRuneId = result.rune.id; markDirty(); render();
  setToast(`「${result.rune.name}」已刻入，效果开始生效`, "success");
});
elements.undo.addEventListener("click", () => { engine.undo(); markDirty(); render(); });
elements.cancel.addEventListener("click", () => { engine.cancel(); render(); setToast("已取消当前笔画"); });
elements.clear.addEventListener("click", () => elements.dialog.showModal());
elements.confirmClear.addEventListener("click", () => { engine.reset(); markDirty(); render(); setToast("阵面已清空"); });
elements.save.addEventListener("click", () => {
  const time = CircleStorage.save(engine.export());
  dirty = false;
  elements.saveStatus.textContent = `已保存 · ${time.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })}`;
  elements.saveStatus.classList.remove("is-dirty");
  setToast("魔法阵已保存在这台设备上", "success");
});
elements.handdrawToggle.addEventListener("change", () => {
  freehandMode = elements.handdrawToggle.checked;
  elements.handdrawStatus.textContent = freehandMode ? "开启" : "关闭";
  elements.handdrawStatus.classList.toggle("is-on", freehandMode);
  setToast(freehandMode ? "模拟绘画已开启：松手后才会吸附并识别" : "已切换回精准蜂窝模式", freehandMode ? "success" : "neutral");
});
elements.helpButton.addEventListener("click", () => elements.helpDialog.showModal());
elements.closeHelp.addEventListener("click", () => elements.helpDialog.close());
elements.helpDialog.addEventListener("click", (event) => {
  if (event.target === elements.helpDialog) elements.helpDialog.close();
});
elements.book.addEventListener("click", (event) => {
  const card = event.target.closest("[data-rune]");
  if (!card) return;
  selectedRuneId = card.dataset.rune; renderBook();
});
elements.activeList.addEventListener("change", (event) => {
  const uid = event.target.dataset.toggle;
  if (!uid) return;
  engine.toggle(uid); markDirty(); render();
});
elements.activeList.addEventListener("click", (event) => {
  const uid = event.target.dataset.remove;
  if (!uid) return;
  engine.remove(uid); markDirty(); render(); setToast("符文已从阵面移除");
});
elements.relicList.addEventListener("dragstart", (event) => {
  const card = event.target.closest("[data-relic]");
  if (!card || card.classList.contains("is-placed")) { event.preventDefault(); return; }
  event.dataTransfer.effectAllowed = "move";
  event.dataTransfer.setData("text/x-relic", card.dataset.relic);
  activeRelicId = card.dataset.relic;
  card.classList.add("is-dragging");
});
elements.relicList.addEventListener("dragend", (event) => {
  event.target.closest("[data-relic]")?.classList.remove("is-dragging");
  activeRelicId = ""; relicGhost = null; renderBoard();
});
elements.relicList.addEventListener("click", (event) => {
  const uid = event.target.dataset.recall;
  if (!uid) return;
  engine.removeRelic(uid); markDirty(); render(); setToast("奇物已回收到左侧奇物匣");
});
elements.relicList.addEventListener("pointerdown", (event) => {
  if (event.button !== 0 || event.target.closest("button")) return;
  const card = event.target.closest("[data-relic]");
  if (!card || card.classList.contains("is-placed")) return;
  event.preventDefault();
  activeRelicId = card.dataset.relic;
  card.classList.add("is-dragging");
});
document.addEventListener("pointermove", (event) => {
  if (!activeRelicId) return;
  const rect = elements.board.getBoundingClientRect();
  const inside = event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom;
  const cell = inside ? nearestCellFromPointer(event) : null;
  relicGhost = cell ? { relicId: activeRelicId, ...engine.previewRelic(activeRelicId, cell) } : null;
  renderBoard();
});
document.addEventListener("pointerup", (event) => {
  if (!activeRelicId) return;
  const relicId = activeRelicId;
  const rect = elements.board.getBoundingClientRect();
  const inside = event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom;
  const cell = inside ? nearestCellFromPointer(event) : null;
  const result = cell ? engine.placeRelic(relicId, cell) : null;
  activeRelicId = ""; relicGhost = null;
  if (result?.ok) {
    markDirty(); render(); setToast(`独一奇物「${result.definition.name}」已置入阵面`, "success");
  } else {
    render();
    if (cell) setToast("这里放不下：奇物不能越界或覆盖已占用蜂窝", "error");
  }
});
elements.board.addEventListener("dragover", (event) => {
  const relicId = activeRelicId;
  if (!relicId) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = "move";
  const cell = nearestCellFromPointer(event);
  relicGhost = cell ? { relicId, ...engine.previewRelic(relicId, cell) } : null;
  renderBoard();
});
elements.board.addEventListener("dragleave", (event) => {
  if (!elements.board.contains(event.relatedTarget)) { relicGhost = null; renderBoard(); }
});
elements.board.addEventListener("drop", (event) => {
  event.preventDefault();
  const relicId = event.dataTransfer.getData("text/x-relic") || activeRelicId;
  const cell = nearestCellFromPointer(event);
  const result = cell && engine.placeRelic(relicId, cell);
  activeRelicId = ""; relicGhost = null;
  if (!result?.ok) { renderBoard(); setToast("这里放不下：奇物不能越界或覆盖已占用蜂窝", "error"); return; }
  markDirty(); render(); setToast(`独一奇物「${result.definition.name}」已置入阵面`, "success");
});

function nearestCellFromPointer(event) {
  const point = pointerToSvg(event);
  let best = null; let bestDistance = 42;
  cells.forEach((cell) => {
    const [x, y] = axialToPoint(cell, 34, [380, 325]);
    const d = Math.hypot(point[0] - x, point[1] - y);
    if (d < bestDistance) { best = cell; bestDistance = d; }
  });
  return best;
}
document.addEventListener("keydown", (event) => {
  if (event.key === "Backspace" && engine.draft.length) { event.preventDefault(); engine.undo(); markDirty(); render(); }
  if (event.key === "Escape" && engine.draft.length) { engine.cancel(); render(); }
  if (event.key === "Enter" && engine.draft.length) elements.commit.click();
});
window.addEventListener("beforeunload", (event) => { if (dirty) event.preventDefault(); });

const saved = CircleStorage.load();
if (saved) {
  engine.import(saved);
  elements.saveStatus.textContent = "已载入本机存档";
}
render();
