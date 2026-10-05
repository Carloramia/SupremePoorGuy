import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const sources = [
  "js/rune-definitions.js",
  "js/relic-definitions.js",
  "js/hex-grid.js",
  "js/rune-engine.js",
  "js/storage.js",
  "js/app.js",
];

const parts = [];
for (const relativePath of sources) {
  let source = await readFile(join(root, relativePath), "utf8");
  source = source
    .replace(/^import\s+[^;]+;\s*$/gm, "")
    .replace(/^export\s+/gm, "");
  parts.push(`// ---- ${relativePath} ----\n${source.trim()}\n`);
}

const banner = `/* Generated file. Edit the modular files in js/ and run npm run build. */\n(() => {\n"use strict";\n`;
const footer = `\n})();\n`;
await writeFile(join(root, "js/browser-bundle.js"), banner + parts.join("\n") + footer, "utf8");
console.log("Built js/browser-bundle.js for direct file opening");
