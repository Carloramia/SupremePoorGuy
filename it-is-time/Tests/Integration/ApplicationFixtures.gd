extends RefCounted

static func complete_opening(app: Node) -> void:
	while app.session.opening_event_pending():
		assert(app.session.advance_opening_event(),app.session.last_error)
	app.ui._close_all()

static func add_human(session: RefCounted) -> void:
	var unit: Dictionary = session.FACTORY.template("human")
	unit.merge({"id":"test_human","position":"team","traits":[]},true)
	session.data.monsters.append(unit)
	assert(session.save(),session.last_error)
