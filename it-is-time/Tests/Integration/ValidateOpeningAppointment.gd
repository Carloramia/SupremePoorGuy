extends "res://Tests/Integration/ValidateStoryEventBoundaries.gd"
## Compatibility test entry: native story state replaces the retired opening_event API.
## All real UI, persistence, cancellation, settings and receipt assertions live in the parent.
func run() -> void:
	await super.run()
	print("OPENING_APPOINTMENT_","PASSED" if failures==0 else "FAILED"," checks=",checks)
