"""Loopback-only, same-origin file-backed monster gallery. No third-party packages."""
import argparse
import json
import os
import re
import shutil
import time
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
import threading
import webbrowser

ROOT = Path(__file__).resolve().parent
WORKS = ROOT / '作品库'
LIMIT = 64 * 1024 * 1024
LOCK = threading.Lock()

def work_path(key):
    if not re.fullmatch(r'[a-zA-Z0-9-]{1,80}', key):
        raise ValueError('作品标识无效')
    path = (WORKS / (key + '.work.json')).resolve()
    if path.parent != WORKS.resolve():
        raise ValueError('路径越界')
    return path

def validate_record(data, key):
    if not isinstance(data, dict):
        raise ValueError('作品必须为对象')
    if data.get('schema') != 'monster-work' or data.get('version') != 1 or data.get('id') != key:
        raise ValueError('作品格式无效')
    if not isinstance(data.get('name'), str) or not 0 < len(data['name']) <= 100:
        raise ValueError('作品名称无效')
    if not isinstance(data.get('preview'), str) or not data['preview'].startswith('data:image/png;base64,'):
        raise ValueError('预览格式无效')
    if not isinstance(data.get('updatedAt', ''), str):
        raise ValueError('保存时间无效')
    project = data.get('project', {})
    if not isinstance(project, dict):
        raise ValueError('方案结构无效')
    if project.get('schema') != 'monster-assembly' or project.get('version') not in (1, 2) or not isinstance(project.get('parts'), list) or len(project['parts']) > 60 or not isinstance(project.get('assets'), list) or len(project['assets']) > 200:
        raise ValueError('方案结构无效')
    return data

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def send_json(self, data, status=200):
        blob = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(blob)))
        self.end_headers()
        self.wfile.write(blob)

    def allowed(self):
        # Reject remote Host headers and cross-origin requests, including null/file origins.
        expected = f'127.0.0.1:{self.server.server_port}'
        return self.headers.get('Host') == expected and self.headers.get('Origin') in (None, 'http://' + expected)

    def do_GET(self):
        path = urlparse(self.path).path
        if not path.startswith('/api/'):
            return super().do_GET()
        if not self.allowed():
            return self.send_json({'error': '仅允许本机同源访问'}, 403)
        try:
            if path == '/api/works':
                items = []
                for p in WORKS.glob('*.work.json'):
                    try:
                        if p.stat().st_size > LIMIT:
                            continue
                        data = validate_record(json.loads(p.read_text(encoding='utf-8')), p.name[:-10])
                        items.append({k: data.get(k, '') for k in ('id', 'name', 'preview', 'updatedAt')})
                    except (ValueError, OSError, KeyError, TypeError):
                        continue
                return self.send_json(sorted(items, key=lambda d: d['updatedAt'], reverse=True))
            if path.startswith('/api/works/'):
                p = work_path(path[len('/api/works/'):])
                return self.send_json(json.loads(p.read_text(encoding='utf-8')))
            return self.send_json({'error': '接口不存在'}, 404)
        except FileNotFoundError:
            return self.send_json({'error': '作品不存在'}, 404)
        except (ValueError, OSError):
            return self.send_json({'error': '无法读取作品'}, 400)

    def do_PUT(self):
        if not self.allowed():
            return self.send_json({'error': '仅允许本机同源写入'}, 403)
        try:
            path = urlparse(self.path).path
            if not path.startswith('/api/works/'):
                return self.send_json({'error': '接口不存在'}, 404)
            key = path[len('/api/works/'):]
            target = work_path(key)
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= LIMIT:
                return self.send_json({'error': '作品大小上限 64 MB'}, 413)
            data = validate_record(json.loads(self.rfile.read(size)), key)
            WORKS.mkdir(exist_ok=True)
            with LOCK:
                if target.exists():
                    history = WORKS / '历史备份'
                    history.mkdir(exist_ok=True)
                    shutil.copy2(target, history / f'{key}-{time.time_ns()}.work.json')
                temporary = target.with_suffix('.tmp')
                temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
                os.replace(temporary, target)
            return self.send_json({'saved': key})
        except (ValueError, OSError, KeyError, TypeError) as error:
            return self.send_json({'error': str(error)}, 400)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--open', action='store_true')
    args = parser.parse_args()
    WORKS.mkdir(exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'Monster workspace: http://127.0.0.1:{args.port}/', flush=True)
    if args.open:
        webbrowser.open(f'http://127.0.0.1:{args.port}/')
    server.serve_forever()
