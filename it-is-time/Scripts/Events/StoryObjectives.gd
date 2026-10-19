extends RefCounted
const CONTENT=preload("res://Scripts/Events/StoryEventContent.gd")
var content:=CONTENT.new()
func target(data: Dictionary, id: String) -> String:
	var e: Dictionary=data.get("story_events",{}).get("entries",{}).get(id,{})
	if id=="QST_SIDE_002_001" and e.get("stage")=="active" and not e.get("defense_won",false): return "hex_camp_mv9za92d_38"
	var entrance: String=""
	if id=="QST_GRASS_012" and e.get("stage")=="await_enchanter": entrance="enchanter"
	if id=="QST_GRASS_007" and e.get("stage")!="return_dialogue": entrance="merchant" if "donkey" in e.get("seen",[]) else "donkey"
	for b: Dictionary in content.catalog.bindings:
		if b.event_id==id and not b.auxiliary and (entrance.is_empty() or b.entrance==entrance): return b.source_id
	return ""
func rows(data: Dictionary) -> Array:
	var result: Array=[]
	for id: String in data.get("story_events",{}).get("entries",{}):
		var e: Dictionary=data.story_events.entries[id]
		if not content.events.has(id) or id=="QST_MAIN_001_001" or not e.get("triggered",false): continue
		var description: String="返回事件地点继续交谈。"
		if e.get("completed",false): description="此事件已经完成，奖励只结算一次。"
		elif not e.get("pending",{}).is_empty(): description="有已保存的操作或战斗，点击继续；不会重新扣费或抽取阵容。"
		elif id=="QST_SIDE_002_001": description="返回城主领取报酬。" if e.get("defense_won",false) else "清剿指定敌营后返回城主。"
		elif id=="QST_GRASS_007": description="双方已经找到彼此，返回交谈。" if e.get("stage")=="return_dialogue" else "寻找老驴与商人。"
		elif id=="QST_GRASS_012" and e.get("stage")=="await_enchanter": description="前往城内寻找附魔师。"
		elif id=="QST_SIDE_003_001": description={"available":"需要一只有毛怪物；献祭后至少保留一只。","stage_2":"需要两只会飞的怪物；献祭后至少保留一只。","stage_3":"需要三只无手无脚的蛇；献祭后至少保留一只。"}.get(e.stage,description)
		elif id=="QST_GRASS_020": description="已结算 %d / 4 轮；继续下一场真实观战。"%int(e.rounds)
		result.append({"id":"story:"+id,"title":content.events[id].title,"description":description,"done":e.get("completed",false),"action":"world"})
	return result
