extends RefCounted
## Palette for temporary vector illustrations only. UI widgets use the editable Theme.
const INK = Color("263b3b")
const PAPER = Color("eee2c8")
const MUTED = Color("67766a")
const GOLD = Color("bc8942")
const TEAL = Color("376f68")
const RED = Color("a45243")

static func make_theme() -> Theme:
	return preload("res://Assets/UI/PrototypeTheme.tres")
