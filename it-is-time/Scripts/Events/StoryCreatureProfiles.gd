extends RefCounted
const FACTORY=preload("res://Scripts/Application/CreatureFactory.gd")
const PATH:="res://Content/Events/ApprovedStoryProfiles.json"
var definitions: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PATH))
func make(id: String, instance_id: String) -> Dictionary:
	if not definitions.profiles.has(id): return {}
	var p: Dictionary=definitions.profiles[id]
	var record:=FACTORY.template(p.species)
	if record.is_empty(): return {}
	record.merge({"id":instance_id,"position":"warehouse","traits":[],"damage_multiplier":float(p.get("attack",1)),"size_multiplier":float(p.get("scale",1))},true)
	record.large=record.large or float(record.size_multiplier)>=1.5
	record.hp=0.0
	for part: Dictionary in record.parts.values(): part.hp*=float(p.get("hp",1)); record.hp+=part.hp
	record.attack*=float(p.get("attack",1))
	return record
func roster(config: Dictionary, prefix: String) -> Array:
	var result: Array=[]
	for id: String in config.get("profiles",[]):
		var record:=make(id,prefix+"_"+str(result.size()))
		if record.is_empty(): return []
		result.append(record)
	return result
