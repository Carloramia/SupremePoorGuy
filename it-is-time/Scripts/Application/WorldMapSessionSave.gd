extends WorldMapSaveService
signal failed(message: String)
var session: RefCounted
var map_id := "frontier"
var loading := false

func save_state(state: WorldMapRuntimeState, _path: String = DEFAULT_PATH) -> bool:
	if loading: return true
	var success: bool = session.commit_battle(session.pending_result,state.to_dict()) if not session.pending_result.is_empty() else session.save_world(state.to_dict())
	last_error = session.last_error
	if not success:
		failed.emit(last_error)
		session.trace("save_failure",{"reason":last_error})
	return success

func load_state(_path: String = DEFAULT_PATH) -> WorldMapRuntimeState:
	var snapshot: Dictionary = session.data.worlds.get(map_id,{})
	if snapshot.is_empty() or not validate_save_data(snapshot): return null
	return WorldMapRuntimeState.from_dict(snapshot)
