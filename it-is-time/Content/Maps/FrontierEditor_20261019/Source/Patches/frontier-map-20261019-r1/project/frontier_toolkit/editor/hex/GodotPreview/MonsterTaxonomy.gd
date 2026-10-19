extends RefCounted
const TYPES=["snake","humanoid","beast","spider","flying"]
const FORMS=["蛇形","人形","兽形","蜘蛛形","飞行类"]
const SIZES=["","tiny","small","medium","large","huge"]
const SIZE_NAMES={"":"待设定","tiny":"微型","small":"小型","medium":"中型","large":"大型","huge":"巨型"}
static func infer_form(site:Dictionary) -> String:
	var text:=str(site.get("name",""))+" "+str(site.get("source_id",""))
	if not str(site.get("id","")).begins_with("hex_"):text+=" "+str(site.get("id",""))
	text=text.to_lower()
	for pair in [["spider",["spider","蜘蛛"]],["snake",["snake","serpent","蛇"]],["humanoid",["bandit","强盗","人形"]],["beast",["wolf","rat","beast","狼","鼠","巨兽","兽形"]]]:
		for token in pair[1]:
			if token in text:return pair[0]
	return "unassigned"

static func upgrade_site(site:Dictionary) -> Dictionary:
	if site.get("kind",site.get("type",""))!="camp" or int(site.get("monster_taxonomy_version",0))>=2:return site
	var sizes:={"small_swarm":"small","medium":"medium","large":"large"}
	for role in ["primary","secondary"]:
		var field:String=role+"_type";var old:String=str(site.get(field,""))
		if role=="secondary" and old.is_empty():
			site[role+"_size"]=site.get(role+"_size","");site[role+"_grouped"]=site.get(role+"_grouped",false);continue
		if sizes.has(old):
			site["legacy_"+field]=site.get("legacy_"+field,old)
			site[field]=infer_form(site) if role=="primary" else "unassigned"
			site[role+"_size"]=site.get(role+"_size",sizes[old]);site[role+"_grouped"]=site.get(role+"_grouped",old=="small_swarm")
		else:
			if role=="primary" and old.is_empty():site[field]="unassigned"
			site[role+"_size"]=site.get(role+"_size","");site[role+"_grouped"]=site.get(role+"_grouped",false)
	site.monster_taxonomy_version=2
	return site

static func upgrade_layout(value:Dictionary) -> Dictionary:
	if int(value.get("monster_taxonomy_version",0))>=2:return value
	var result:=value.duplicate(true)
	for site in result.get("sites",[]):
		if site is Dictionary:upgrade_site(site)
	result.monster_taxonomy_version=2
	return result

static func duplicate_roles(site:Dictionary) -> bool:
	if str(site.get("secondary_type","")).is_empty() or site.get("primary_type")=="unassigned" or site.get("secondary_type")=="unassigned":return false
	return site.get("primary_type","")==site.get("secondary_type","") and site.get("primary_size","")==site.get("secondary_size","") and site.get("primary_grouped",false)==site.get("secondary_grouped",false)

static func size_for_scale(scale:float) -> String:
	return "tiny" if scale<=.4 else "small" if scale<.8 else "huge" if scale>=2.5 else "large" if scale>1.25 else "medium"
