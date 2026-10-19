extends RefCounted
## Native runtime assets. Source/Exports and writing drafts are never executed.
const BASE := "res://Content/Events/Current/"
const CONFIGURATION = preload("res://Scripts/Events/StoryConfiguration.gd")
const OPERATIONS := ["","close","flag","appointment","money","require_money","both_seen","require_role","attack_check","shell_reward","reward","buy_engine","pickup","sacrifice","battle","bet","monster_reward"]
static var _texts: Dictionary = {}
static var _flows: Dictionary = {}
static var _parameters: Dictionary = {}

static func _read(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE+name+".json"))
	return value if value is Dictionary else {}

static func texts() -> Dictionary:
	if _texts.is_empty(): _texts=_read("texts")
	var events: Variant = _texts.get("events",{})
	return events if events is Dictionary else {}

static func flows() -> Dictionary:
	if _flows.is_empty(): _flows=_read("flows")
	return _flows

static func parameters() -> Dictionary:
	if _parameters.is_empty(): _parameters=_read("parameters")
	return _parameters

static func definition(id: String) -> Dictionary:
	var flow: Variant = flows().get(id,{})
	return flow if flow is Dictionary else {}

static func title(id: String) -> String:
	return str(texts().get(id,{}).get("title",id))

static func paragraph(id: String, reference: Variant) -> String:
	var index: int = int(reference.get("index",0)) if reference is Dictionary else int(reference)
	var paragraphs: Array = texts().get(id,{}).get("paragraphs",[])
	if index<0 or index>=paragraphs.size(): return ""
	var lines := str(paragraphs[index]).split("\n")
	var selected: Array = reference.get("lines",[]) if reference is Dictionary else []
	var visible: Array[String] = []
	for line_index: int in lines.size():
		if not selected.is_empty() and not selected.any(func(value):return int(value)==line_index): continue
		var line := lines[line_index].strip_edges()
		if line.begins_with("（") or line.begins_with("(") or line.begins_with("【") or line.begins_with("#") or line.begins_with("|"): continue
		visible.append(line.replace("**",""))
	return "\n".join(visible)

static func bindings(id: String, map_version: String = "20261019", configured: Dictionary = {}) -> Array:
	var catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
	var result: Array = []
	for site: Dictionary in catalog.world(map_version).get("objects",[]):
		if site.get("event_id","")==id and site.get("event_trigger",{}).get("enabled",true):
			result.append({"source_id":site.id,"entry_role":site.get("event_trigger",{}).get("stage_id",""),"trigger_mode":site.get("event_trigger",{}).get("mode","interact")})
		for link: Dictionary in site.get("event_links",[]):
			if link.get("event_id","")==id and link.get("event_trigger",{}).get("enabled",true): result.append({"source_id":site.id,"entry_role":link.get("entry_role",""),"trigger_mode":link.get("event_trigger",{}).get("mode","interact")})
	if id=="QST_SIDE_002_001":
		var values: Dictionary = configured if not configured.is_empty() else parameters()
		var p: Variant = values.get(id,{})
		if not p is Dictionary or not p.get("battles",{}) is Dictionary: return result
		var clear: Variant = p.get("battles",{}).get("clear",{})
		if not clear is Dictionary: return result
		var source: Variant = clear.get("source_id")
		if source is String and not catalog.location_for_version(source,map_version).is_empty(): result.append({"source_id":source,"entry_role":"clear_target","trigger_mode":"interact"})
	return result

static func validate() -> String:
	return validate_assets(flows(),texts(),parameters())

static func validate_assets(flow_data: Variant, text_data: Variant, parameter_data: Variant) -> String:
	if not flow_data is Dictionary or not text_data is Dictionary: return "事件执行图和正文必须是字典。"
	if text_data.size()!=23 or flow_data.size()!=23: return "正式事件目录不完整。"
	var parameter_error := CONFIGURATION.error(parameter_data)
	if not parameter_error.is_empty(): return parameter_error
	for id: String in flow_data:
		var raw: Variant = flow_data[id]
		if not raw is Dictionary or not raw.get("nodes") is Dictionary: return "事件节点必须为字典："+id
		var flow: Dictionary = raw
		if not text_data.has(id) or not text_data[id] is Dictionary or not text_data[id].get("paragraphs") is Array: return "事件正文无效："+id
		if not flow.get("start") is String or not flow.nodes.has(flow.start): return "事件入口不存在："+id
		for key: String in flow.nodes:
			if not flow.nodes[key] is Dictionary: return "事件节点格式无效："+id+":"+key
			var node: Dictionary = flow.nodes[key]
			if node.get("type") not in ["dialogue","choice","action","end","blocked","container"]: return "未知事件节点："+id+":"+key
			if not node.get("paragraphs",[]) is Array or not node.get("options",[]) is Array: return "段落和选项必须为数组："+id+":"+key
			if node.type=="action" and (not node.get("label") is String or not node.get("action") is Dictionary): return "操作节点缺少按钮文字或操作："+id+":"+key
			if node.type=="choice" and node.get("options",[]).is_empty(): return "选择节点没有选项："+id+":"+key
			if node.type=="dialogue" and (node.get("paragraphs",[]).is_empty() or not flow.nodes.has(node.get("next",""))): return "对白跳转缺失："+id+":"+key
			for reference: Variant in node.get("paragraphs",[]):
				var index: Variant = reference.get("index") if reference is Dictionary else reference
				if not CONFIGURATION.integer(index) or int(index)>=text_data[id].paragraphs.size(): return "段落引用越界："+id+":"+key
				if not text_data[id].paragraphs[int(index)] is String: return "段落正文不是字符串："+id+":"+key
				if reference is Dictionary:
					if not reference.get("lines",[]) is Array: return "正文行号必须为数组："+id+":"+key
					for line: Variant in reference.get("lines",[]):
						if not CONFIGURATION.integer(line) or int(line)>=text_data[id].paragraphs[int(index)].split("\n").size(): return "正文行号越界："+id+":"+key
				if paragraph(id,reference).is_empty(): return "正文引用为空："+id+":"+key
			var seen := {}
			var commands: Array = node.get("options",[]).duplicate()
			if node.has("action"): commands.append({"id":"confirm","action":node.action})
			for raw_item: Variant in commands:
				if not raw_item is Dictionary or not raw_item.get("id") is String or not raw_item.get("action",{}) is Dictionary: return "事件选项格式无效："+id+":"+key
				var item: Dictionary = raw_item
				if node.type=="choice" and not item.get("label") is String: return "事件选项缺少按钮文字："+id+":"+key
				if seen.has(item.id): return "重复选项："+id+":"+key
				seen[item.id]=true
				if item.get("action",{}).get("op","") not in OPERATIONS: return "未知事件操作："+id+":"+key
				for target: String in [str(item.get("next","")),str(item.get("action",{}).get("next","")),str(item.get("action",{}).get("won","")),str(item.get("action",{}).get("lost","")),str(item.get("action",{}).get("passed","")),str(item.get("action",{}).get("failed",""))]:
					if not target.is_empty() and not flow.nodes.has(target): return "事件跳转不存在："+id+":"+target
	return ""
