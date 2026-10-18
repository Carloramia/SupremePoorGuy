@tool
extends Node
## JSON is the source of truth; native translations also cover authored Control text.
signal locale_changed(locale: String)
const CONFIG := "res://Localization/config.json"
var settings_path := "user://settings/language.cfg"
static var _sources: Dictionary = {}
static var _aliases: Dictionary = {}
static var _bindings: Dictionary = {}
var configuration: Dictionary = {}
var _translations: Array[Translation] = []

static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:
		push_error("[localization] Invalid JSON: "+path)
		return {}
	return parser.data

static func _ensure_sources() -> void:
	if not _sources.is_empty(): return
	var entries: Dictionary = _json("res://Localization/catalog.json").get("messages",{})
	for key: String in entries:
		var entry: Dictionary = entries[key]
		_sources[key] = entry.source
		_aliases[entry.source] = key

static func text(key_or_source: String, values: Dictionary = {}) -> String:
	_ensure_sources()
	var key: String = _aliases.get(key_or_source,key_or_source)
	var result := String(TranslationServer.translate(key))
	if result==key: result = _sources.get(key,key_or_source)
	return result.format(values) if not values.is_empty() else result

static func creature_name(record: Dictionary) -> String:
	var original: String = record.get("name","")
	if record.get("custom_name",false): return original
	var key := "creature."+String(record.get("definition_id",""))+".name"
	_ensure_sources()
	# Old saves have no rename flag; differing names are treated as player-authored.
	return text(key) if _sources.get(key,"")==original else original

static func prose(source: String) -> String:
	_ensure_sources()
	if _sources.has(source) or _aliases.has(source): return text(source)
	return "\n".join(Array(source.split("\n")).map(func(line): return text(line)))

## A builder retains the original template and values, rather than a translated snapshot.
## Bindings exist only for live controls and refresh only on a locale change.
static func bind(control: Node, property: StringName, builder: Variant) -> void:
	control.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var token := str(control.get_instance_id())+":"+String(property)
	if not _bindings.has(token): control.tree_exiting.connect(func(): _bindings.erase(token),CONNECT_ONE_SHOT)
	_bindings[token] = {"control":weakref(control),"property":property,"builder":builder}
	_refresh_binding(_bindings[token])

static func _refresh_binding(binding: Dictionary) -> void:
	var control: Node = binding.control.get_ref()
	if not is_instance_valid(control): return
	var builder: Variant = binding.builder
	if builder is Callable and not builder.is_valid(): return
	control.set(binding.property,builder.call() if builder is Callable else text(str(builder)))

static func refresh_bindings() -> void:
	for token: String in _bindings.keys():
		if not is_instance_valid(_bindings[token].control.get_ref()): _bindings.erase(token)
		else: _refresh_binding(_bindings[token])

func _ready() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	configuration = _json(CONFIG)
	_ensure_sources()
	var fallback: Dictionary = _load_messages(configuration.get("fallback_locale","zh_CN"))
	for locale: String in configuration.get("locales",{}):
		var messages := fallback.duplicate()
		messages.merge(_load_messages(locale),true)
		var translation := Translation.new()
		translation.locale = locale
		for key: String in _sources:
			var value: String = messages.get(key,_sources[key])
			translation.add_message(key,value)
			translation.add_message(_sources[key],value)
		TranslationServer.add_translation(translation)
		_translations.append(translation)
	var preferences := ConfigFile.new()
	var locale: String = configuration.get("default_locale","zh_CN")
	if preferences.load(settings_path)==OK: locale = preferences.get_value("language","locale",locale)
	if not configuration.get("locales",{}).has(locale): locale = configuration.get("fallback_locale","zh_CN")
	set_locale(locale,false)

func _load_messages(locale: String) -> Dictionary:
	var messages := {}
	for file: String in configuration.get("locales",{}).get(locale,{}).get("files",[]):
		var data := _json("res://Localization/"+file)
		if data.get("locale","")!=locale or not data.get("messages") is Dictionary:
			push_error("[localization] Invalid locale file: "+file)
			continue
		for key: String in data.messages:
			if not data.messages[key] is String or String(data.messages[key]).is_empty(): continue
			messages[key] = data.messages[key]
	return messages

func set_locale(locale: String, persist: bool = true) -> bool:
	if not configuration.get("locales",{}).has(locale): return false
	if persist:
		var preferences := ConfigFile.new()
		preferences.set_value("language","locale",locale)
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(settings_path.get_base_dir()))
		if error!=OK or preferences.save(settings_path)!=OK: return false
	TranslationServer.set_locale(locale)
	refresh_bindings()
	locale_changed.emit(locale)
	return true

func current_locale() -> String:
	return TranslationServer.get_locale()

func _exit_tree() -> void:
	for translation: Translation in _translations: TranslationServer.remove_translation(translation)
	_bindings.clear()
