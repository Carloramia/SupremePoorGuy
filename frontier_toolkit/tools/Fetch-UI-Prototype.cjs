// Fetch the pinned upstream snapshot without touching the local Git index.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'ui_module/upstream/source-manifest.json'), 'utf8'));
function hash(data) { return crypto.createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex'); }
async function main() {
  let cursor = 0, completed = 0;
  async function worker() {
    while (cursor < manifest.files.length) {
      const entry = manifest.files[cursor++];
      const target = path.join(root, entry.path);
      if (!target.startsWith(root + path.sep)) throw new Error('Invalid source path');
      if (fs.existsSync(target)) {
        if (hash(fs.readFileSync(target)) !== entry.sha) throw new Error(`Local file differs: ${entry.path}`);
      } else {
        const url = `https://raw.githubusercontent.com/${manifest.repository}/${manifest.commit}/${entry.path.split('/').map(encodeURIComponent).join('/')}`;
        const response = await fetch(url, {signal: AbortSignal.timeout(60000)});
        if (!response.ok) throw new Error(`${response.status}: ${entry.path}`);
        const data = Buffer.from(await response.arrayBuffer());
        if (hash(data) !== entry.sha) throw new Error(`Hash mismatch: ${entry.path}`);
        fs.mkdirSync(path.dirname(target), {recursive: true});
        fs.writeFileSync(target, data);
      }
      completed++;
    }
  }
  await Promise.all(Array.from({length: 8}, worker));
  // Keep the nested reference project out of the host's resource scan.
  fs.writeFileSync(path.join(root, 'UI跳转原型/.gdignore'), '\n');
  console.log(`Verified ${completed} upstream files at ${manifest.commit}`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
