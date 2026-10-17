"""Copy the two runtime modules without project settings, caches or user data."""
from pathlib import Path
import json

PROJECT = Path(__file__).resolve().parents[2]
SOURCES = {
    "PaperUI": (PROJECT.parent / "UI跳转原型", ["Scripts", "Scenes/UI", "Scenes/GameDemo.tscn", "Assets/UI"]),
    "Frontier": (PROJECT.parent / "frontier_toolkit", ["world_map", "scenario_2_5d", "integration", "LICENSE_NOTICE.md"]),
}
TEXT = {".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".svg"}
ASSETS = TEXT | {".uid", ".png", ".jpg", ".webp", ".ttf", ".otf", ".txt", ".md"}
SKIP = {"debug", "docs", "tools", "Tests", "tests", "screenshots", "previews", ".godot"}

def sync():
    if any((PROJECT / "Modules" / module).exists() for module in SOURCES):
        raise SystemExit("Runtime modules already exist. Refusing to overwrite integration changes; compare upstream explicitly.")
    manifest = {}
    for module, (source, entries) in SOURCES.items():
        destination = PROJECT / "Modules" / module
        files = []
        for entry in entries:
            path = source / entry
            for item in ([path] if path.is_file() else path.rglob("*")):
                relative = item.relative_to(source)
                if not item.is_file() or item.suffix not in ASSETS or (SKIP.intersection(relative.parts) and not item.name.startswith("hex_debug_overlay.")):
                    continue
                if "_tests." in item.name or "_preview." in item.name:
                    continue
                target = destination / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                if item.suffix in TEXT:
                    text = item.read_text(encoding="utf-8-sig").replace("res://", f"res://Modules/{module}/")
                    target.write_text(text, encoding="utf-8", newline="\n")
                else:
                    target.write_bytes(item.read_bytes())
                files.append(relative.as_posix())
        manifest[module] = {"source": str(source), "files": sorted(files)}
    (PROJECT / "Modules" / "sources.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print({key: len(value["files"]) for key, value in manifest.items()})

if __name__ == "__main__":
    sync()
