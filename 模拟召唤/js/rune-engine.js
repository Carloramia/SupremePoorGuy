import { distance, keyOf, sameOrderedShape, transformPath } from "./hex-grid.js";

/** Pure game-state module. It does not know about DOM, SVG, pointer events or storage. */
export class RuneEngine {
  constructor(definitions, validCells, relicDefinitions = []) {
    this.definitions = definitions;
    this.relicDefinitions = relicDefinitions;
    this.validCells = new Set(validCells.map(keyOf));
    this.reset();
  }

  reset() {
    this.draft = [];
    this.placed = [];
    this.placedRelics = [];
    this.occupied = new Map();
  }

  begin(cell) {
    if (!this.canUse(cell)) return { ok: false, reason: "occupied" };
    this.draft = [cell];
    return { ok: true };
  }

  extend(cell) {
    if (!this.canUse(cell)) return { ok: false, reason: "occupied" };
    if (this.draft.some((item) => keyOf(item) === keyOf(cell))) return { ok: false, reason: "repeated" };
    if (this.draft.length && distance(this.draft.at(-1), cell) !== 1) return { ok: false, reason: "not-adjacent" };
    this.draft.push(cell);
    return { ok: true };
  }

  undo() {
    return this.draft.pop() ?? null;
  }

  cancel() {
    this.draft = [];
  }

  canUse(cell) {
    const key = keyOf(cell);
    return this.validCells.has(key) && !this.occupied.has(key);
  }

  recognize(path = this.draft) {
    for (const rune of this.definitions) {
      if (rune.cells.length !== path.length) continue;
      for (const mirrored of [false, true]) {
        for (let rotations = 0; rotations < 6; rotations += 1) {
          const transformed = transformPath(rune.cells, rotations, mirrored);
          // A rune has a shape, not a mandatory stroke direction. Accept the
          // same connected path when the player starts at the opposite end.
          if (sameOrderedShape(path, transformed) || sameOrderedShape(path, [...transformed].reverse())) return rune;
        }
      }
    }
    return null;
  }

  commit() {
    const rune = this.recognize();
    if (!rune) return { ok: false, reason: "unknown-shape" };
    const placedRune = {
      uid: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      runeId: rune.id,
      cells: this.draft.map((cell) => [...cell]),
      enabled: true,
    };
    this.placed.push(placedRune);
    placedRune.cells.forEach((cell) => this.occupied.set(keyOf(cell), placedRune.uid));
    this.draft = [];
    return { ok: true, placedRune, rune };
  }

  toggle(uid) {
    const item = this.placed.find((rune) => rune.uid === uid);
    if (!item) return null;
    item.enabled = !item.enabled;
    return item;
  }

  remove(uid) {
    const index = this.placed.findIndex((rune) => rune.uid === uid);
    if (index < 0) return false;
    const [removed] = this.placed.splice(index, 1);
    removed.cells.forEach((cell) => this.occupied.delete(keyOf(cell)));
    return true;
  }

  placeRelic(relicId, anchor) {
    const definition = this.relicDefinitions.find((relic) => relic.id === relicId);
    if (!definition) return { ok: false, reason: "unknown-relic" };
    if (this.placedRelics.some((relic) => relic.relicId === relicId)) return { ok: false, reason: "already-placed" };
    const cells = definition.cells.map(([q, r]) => [q + anchor[0], r + anchor[1]]);
    if (cells.some((cell) => !this.canUse(cell))) return { ok: false, reason: "blocked" };
    const placedRelic = {
      uid: globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      relicId,
      cells,
    };
    this.placedRelics.push(placedRelic);
    cells.forEach((cell) => this.occupied.set(keyOf(cell), placedRelic.uid));
    return { ok: true, placedRelic, definition };
  }

  removeRelic(uid) {
    const index = this.placedRelics.findIndex((relic) => relic.uid === uid);
    if (index < 0) return false;
    const [removed] = this.placedRelics.splice(index, 1);
    removed.cells.forEach((cell) => this.occupied.delete(keyOf(cell)));
    return true;
  }

  previewRelic(relicId, anchor) {
    const definition = this.relicDefinitions.find((relic) => relic.id === relicId);
    if (!definition) return null;
    const cells = definition.cells.map(([q, r]) => [q + anchor[0], r + anchor[1]]);
    return {
      cells,
      valid: !this.placedRelics.some((relic) => relic.relicId === relicId) && cells.every((cell) => this.canUse(cell)),
    };
  }

  export() {
    return { version: 2, placed: structuredClone(this.placed), placedRelics: structuredClone(this.placedRelics) };
  }

  import(payload) {
    this.reset();
    if (!payload || ![1, 2].includes(payload.version) || !Array.isArray(payload.placed)) return false;
    for (const item of payload.placed) {
      if (!this.definitions.some((rune) => rune.id === item.runeId)) continue;
      if (!Array.isArray(item.cells) || item.cells.some((cell) => !this.canUse(cell))) continue;
      const restored = { uid: item.uid || `${Date.now()}-${Math.random()}`, runeId: item.runeId, cells: item.cells, enabled: item.enabled !== false };
      this.placed.push(restored);
      restored.cells.forEach((cell) => this.occupied.set(keyOf(cell), restored.uid));
    }
    if (payload.version >= 2 && Array.isArray(payload.placedRelics)) {
      for (const item of payload.placedRelics) {
        if (!this.relicDefinitions.some((relic) => relic.id === item.relicId)) continue;
        if (!Array.isArray(item.cells) || item.cells.some((cell) => !this.canUse(cell))) continue;
        if (this.placedRelics.some((relic) => relic.relicId === item.relicId)) continue;
        const restored = { uid: item.uid || `${Date.now()}-${Math.random()}`, relicId: item.relicId, cells: item.cells };
        this.placedRelics.push(restored);
        restored.cells.forEach((cell) => this.occupied.set(keyOf(cell), restored.uid));
      }
    }
    return true;
  }
}
