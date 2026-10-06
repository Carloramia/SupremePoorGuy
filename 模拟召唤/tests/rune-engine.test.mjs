import assert from "node:assert/strict";
import { createHexDisk, hexLine, transformPath } from "../js/hex-grid.js";
import { RUNES } from "../js/rune-definitions.js";
import { RELICS } from "../js/relic-definitions.js";
import { RuneEngine } from "../js/rune-engine.js";

const engine = new RuneEngine(RUNES, createHexDisk(4));
const emberRotated = transformPath(RUNES[0].cells, 2, true);
assert.equal(engine.recognize(emberRotated)?.id, "ember", "recognizes rotated mirrored shapes");
assert.equal(engine.recognize([...RUNES[2].cells].reverse())?.id, "ward", "recognizes the same ward drawn from the opposite end");
assert.deepEqual(hexLine([0, 0], [0, 3]), [[0, 0], [0, 1], [0, 2], [0, 3]], "fills cells skipped by a fast pointer stroke");
assert.equal(engine.recognize(RUNES[4].cells)?.id, "sky-nail", "recognizes the seven-cell sky nail");
assert.equal(engine.recognize(transformPath([...RUNES[5].cells].reverse(), 4, true))?.id, "cycle", "recognizes a reversed, rotated, mirrored cycle");
assert.equal(engine.recognize(transformPath(RUNES[6].cells, 3, false))?.id, "twin-peak", "recognizes the nine-cell twin peak");

engine.begin(emberRotated[0]);
emberRotated.slice(1).forEach((cell) => assert.equal(engine.extend(cell).ok, true));
const committed = engine.commit();
assert.equal(committed.ok, true, "commits a recognized rune");
assert.equal(engine.canUse(emberRotated[0]), false, "prevents shared hex occupancy");

const uid = committed.placedRune.uid;
assert.equal(engine.toggle(uid).enabled, false, "can disable a placed rune");
assert.equal(engine.toggle(uid).enabled, true, "can re-enable a placed rune");

const saved = engine.export();
const restored = new RuneEngine(RUNES, createHexDisk(4));
assert.equal(restored.import(saved), true, "imports a valid save");
assert.equal(restored.placed.length, 1, "restores placed runes");
assert.equal(restored.occupied.size, RUNES[0].cells.length, "restores occupancy map");

const relicEngine = new RuneEngine(RUNES, createHexDisk(4), RELICS);
const relicPlacement = relicEngine.placeRelic("tide-pump", [0, 0]);
assert.equal(relicPlacement.ok, true, "places a complete relic block");
assert.equal(relicEngine.placeRelic("tide-pump", [-3, 0]).reason, "already-placed", "enforces relic uniqueness");
assert.equal(relicEngine.placeRelic("bone-die", [0, 0]).reason, "blocked", "relics share the occupancy rules");
const relicSave = relicEngine.export();
const restoredRelics = new RuneEngine(RUNES, createHexDisk(4), RELICS);
restoredRelics.import(relicSave);
assert.equal(restoredRelics.placedRelics.length, 1, "restores placed relics");

console.log("Rune engine checks passed");
