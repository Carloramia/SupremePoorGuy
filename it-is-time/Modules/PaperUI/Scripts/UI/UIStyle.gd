extends RefCounted
## Palette for temporary vector illustrations only. UI widgets use the editable Theme.
const INK = Color("27231f")
const PAPER = Color("f0e3ce")
const MUTED = Color("60634b")
const GOLD = Color("bd7d32")
const TEAL = Color("60634b")
const RED = Color("94513f")

static func make_theme() -> Theme:
	return preload("res://Modules/PaperUI/Assets/UI/PrototypeTheme.tres")
