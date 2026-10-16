const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawnSync} = require('node:child_process');
const repository = 'Carloramia/SupremePoorGuy';
const commit = 'e97c6994152301127fd07b779e1dc32fc940b9c4';
const directory = 'UI跳转原型';
const root = path.resolve(__dirname, '..');
const cache = path.resolve(root, '../.tools/upstream-ui-20261015');
const hash = data => crypto.createHash('sha1').update('blob ' + data.length + '\0').update(data).digest('hex');
function git(args) {
  const result = spawnSync('git', ['-c', 'http.proxy=', ...args], {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (result.status !== 0) throw new Error(result.stderr || 'Git failed');
  return result.stdout;
}
function main() {
  if (!fs.existsSync(path.join(cache, '.git'))) {
    if (process.argv.includes('--prepare-only')) throw new Error('Sparse source cache missing');
    git(['clone', '--depth', '1', '--filter=blob:none', '--sparse', '--branch', 'main', 'https://github.com/' + repository + '.git', cache]);
    git(['-C', cache, 'sparse-checkout', 'set', directory]);
  }
  if (git(['-C', cache, 'rev-parse', 'HEAD']).trim() !== commit) {
    if (process.argv.includes('--prepare-only')) throw new Error('Cached commit differs');
    git(['-C', cache, 'fetch', '--depth', '1', 'origin', commit]);
    git(['-C', cache, 'checkout', '--detach', commit]);
  }
  const entries = git(['-C', cache, 'ls-tree', '-r', '-z', 'HEAD', '--', directory]).split('\0').filter(Boolean).map(entry => {
    const [meta, fullPath] = entry.split('\t');
    const [mode, type, sha] = meta.split(' ');
    if (type !== 'blob' || mode === '120000') throw new Error('Unsupported source entry: ' + fullPath);
    return {path: fullPath.slice(directory.length + 1), sha, mode};
  });
  let bytes = 0;
  for (const entry of entries) {
    const target = path.resolve(root, entry.path);
    const source = path.resolve(cache, directory, entry.path);
    if (!target.startsWith(root + path.sep) || !source.startsWith(path.join(cache, directory) + path.sep)) throw new Error('Unsafe source path');
    let data = fs.readFileSync(source);
    // Windows checkout may normalize newlines. Preserve canonical Git bytes.
    if (hash(data) !== entry.sha) {
      const blob = spawnSync('git', ['-C', cache, 'cat-file', 'blob', entry.sha], {maxBuffer: 128 * 1024 * 1024});
      if (blob.status !== 0) throw new Error('Cannot read canonical blob: ' + entry.path);
      data = blob.stdout;
    }
    if (hash(data) !== entry.sha) throw new Error('Cached source differs: ' + entry.path);
    if (fs.existsSync(target)) {
      if (hash(fs.readFileSync(target)) !== entry.sha) throw new Error('Refusing to overwrite local edits: ' + entry.path);
    } else {
      fs.mkdirSync(path.dirname(target), {recursive: true});
      fs.writeFileSync(target, data);
    }
    entry.size = data.length;
    bytes += data.length;
  }
  fs.writeFileSync(path.join(__dirname, 'source-manifest.json'), JSON.stringify({repository, commit, sourceDirectory: directory, fetchedDate: '2026-10-15', files: entries}, null, 2) + '\n');
  console.log(JSON.stringify({repository, commit, files: entries.length, bytes, target: root}));
}
try { main(); } catch (error) { console.error(error.message); process.exitCode = 1; }

