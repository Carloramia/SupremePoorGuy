extends RefCounted

static func add_human(session: RefCounted) -> void:
	var unit: Dictionary = session.FACTORY.template("human")
	unit.merge({"id":"test_human","position":"team","traits":[]},true)
	session.data.monsters.append(unit)
	assert(session.save(),session.last_error)
