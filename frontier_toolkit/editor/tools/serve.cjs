const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const port = Number(process.argv[2] || 8765);
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.json': 'application/json; charset=utf-8', '.md': 'text/plain; charset=utf-8' };
http.createServer((request, response) => {
  try {
    let requested = decodeURIComponent(new URL(request.url, 'http://localhost').pathname); if (requested === '/') requested = '/editor/index.html';
    const file = path.resolve(root, '.' + requested), extension = path.extname(file).toLowerCase();
    if (!file.startsWith(root + path.sep) || !types[extension] || requested.split('/').some(part => part.startsWith('.'))) { response.writeHead(403); response.end('Forbidden'); return; }
    fs.readFile(file, (error, data) => { if (error) { response.writeHead(404); response.end('Not found'); return; } response.writeHead(200, { 'Content-Type': types[extension], 'Cache-Control': 'no-cache', 'X-Content-Type-Options': 'nosniff' }); response.end(data); });
  } catch { response.writeHead(400); response.end('Bad request'); }
}).listen(port, '127.0.0.1', () => console.log(`Frontier Studio: http://127.0.0.1:${port}/editor/index.html`));
