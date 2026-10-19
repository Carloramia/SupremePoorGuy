import tempfile
import unittest
from pathlib import Path

from ImportHexMapHandoff import CONTENT, PLANNER, PROJECT, file_refs, remap, resolve
from BuildHexMapRuntime import local, safe_id

TEST_ROOT = PROJECT.parents[1] / 'RuntimeChecks/HexMapHandoff'


class HexHandoffTests(unittest.TestCase):
    def test_runtime_output_ids_cannot_escape_the_version_directory(self):
        self.assertEqual(safe_id('battle_hex_camp_01'), 'battle_hex_camp_01')
        for value in ['../index', '/index', 'C:/temp', '', None]:
            with self.assertRaises(ValueError): safe_id(value)

    def test_runtime_resource_paths_stay_in_the_project(self):
        self.assertTrue(local('res://Content/Maps/map.json').is_relative_to(PROJECT))
        for value in ['res://../outside.png', 'C:/outside.png', 'res://D:/outside.png']:
            with self.assertRaises(ValueError): local(value)

    @classmethod
    def setUpClass(cls):
        assert TEST_ROOT.resolve().is_relative_to(PROJECT.parents[1].resolve())
        TEST_ROOT.mkdir(parents=True, exist_ok=True)

    def test_browser_and_godot_aliases_use_one_asset(self):
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as folder:
            package = Path(folder).resolve()
            source = package / PLANNER / 'assets/tree.png'
            source.parent.mkdir(parents=True)
            source.touch()
            browser = resolve(package, 'assets/tree.png')
            godot = resolve(package, 'res://editor/hex/Tools/hex-planner/assets/tree.png')
            self.assertEqual(browser, godot)
            self.assertEqual(browser[1], CONTENT / 'Assets/HexPlanner/tree.png')

    def test_legacy_hashed_asset_keeps_original(self):
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as folder:
            package = Path(folder).resolve()
            source = package / '美术源文件/历史路径资源/Assets/Maps/hash.svg'
            source.parent.mkdir(parents=True)
            source.touch()
            self.assertEqual(resolve(package, 'res://Assets/Maps/hash.svg'),
                             (source, CONTENT / 'Assets/LegacyMaps/hash.svg'))

    def test_rejects_unresolved_and_escaping_paths(self):
        with tempfile.TemporaryDirectory(dir=TEST_ROOT) as folder:
            package = Path(folder).resolve()
            with self.assertRaises(ValueError):
                resolve(package, 'res://Scripts/Application/GameRoot.gd')
            with self.assertRaises(ValueError):
                resolve(package, 'assets/../../../../../../../../outside.png')
            with self.assertRaises(FileNotFoundError):
                resolve(package, 'assets/missing.png')

    def test_nested_edge_background_is_remapped_without_changing_layout(self):
        data = {'assets': [{'path': 'assets/tree.png', 'edge_background': {'path': 'res://Assets/Maps/edge.svg'}}],
                'position': [3.25, 7], 'width': 85, 'anchor': [0.5, 1], 'definition_id': None}
        self.assertEqual(set(file_refs(data)), {'assets/tree.png', 'res://Assets/Maps/edge.svg'})
        converted = remap(data, {'assets/tree.png': 'res://new/tree.png', 'res://Assets/Maps/edge.svg': 'res://new/edge.svg'})
        self.assertEqual(converted['assets'][0]['edge_background']['path'], 'res://new/edge.svg')
        self.assertEqual(converted['position'], data['position'])
        self.assertEqual(converted['anchor'], data['anchor'])
        self.assertIsNone(converted['definition_id'])
        self.assertEqual(data['assets'][0]['path'], 'assets/tree.png')


if __name__ == '__main__':
    unittest.main()
