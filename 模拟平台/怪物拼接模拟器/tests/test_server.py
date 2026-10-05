import importlib.util
import json
import tempfile
import threading
import unittest
import urllib.request
import urllib.error
from pathlib import Path

spec = importlib.util.spec_from_file_location('workspace_server', Path(__file__).resolve().parents[1] / 'server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

class GalleryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='monster-gallery-test-')
        server.WORKS = Path(self.temp.name) / '作品库'
        server.WORKS.mkdir()
        self.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.base = f'http://127.0.0.1:{self.http.server_port}'
        self.record = {'schema':'monster-work','version':1,'id':'test-work','name':'测试作品','preview':'data:image/png;base64,AAAA','updatedAt':'2026-10-05','project':{'schema':'monster-assembly','version':2,'parts':[],'assets':[]}}

    def tearDown(self):
        self.http.shutdown()
        self.http.server_close()
        self.temp.cleanup()

    def request(self, path, record=None, origin=None):
        headers = {'Content-Type':'application/json'}
        if origin is not None:
            headers['Origin'] = origin
        req = urllib.request.Request(self.base + path, data=json.dumps(record).encode() if record else None, headers=headers, method='PUT' if record else 'GET')
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.load(r)
        except urllib.error.HTTPError as e:
            with e:
                return e.code, json.load(e)

    def test_save_list_load(self):
        self.assertEqual(self.request('/api/works/test-work', self.record)[0], 200)
        self.assertTrue((server.WORKS / 'test-work.work.json').exists())
        self.assertEqual(self.request('/api/works')[1][0]['name'], '测试作品')
        self.assertEqual(self.request('/api/works/test-work')[1]['project'], self.record['project'])

    def test_overwrite_backup(self):
        self.request('/api/works/test-work', self.record)
        self.record['name'] = '修改后'
        self.request('/api/works/test-work', self.record)
        backups = list((server.WORKS / '历史备份').glob('*.work.json'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(json.loads(backups[0].read_text(encoding='utf8'))['name'], '测试作品')

    def test_path_rejection(self):
        self.assertEqual(self.request('/api/works/../outside', self.record)[0], 400)

    def test_cross_origin_rejection(self):
        self.assertEqual(self.request('/api/works/test-work', self.record, 'https://example.invalid')[0], 403)
        self.assertEqual(self.request('/api/works/test-work', self.record, 'null')[0], 403)

    def test_invalid_record(self):
        self.record['project'] = {}
        self.assertEqual(self.request('/api/works/test-work', self.record)[0], 400)
        self.assertFalse((server.WORKS / 'test-work.work.json').exists())

if __name__ == '__main__':
    unittest.main()
