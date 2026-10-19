@tool
extends Resource

## Shared runtime optimization switch. Disabling restores the original calculation path.
@export var enabled: bool = true

## Planning only; attack execution, timers and physical forces still update every physics tick.
@export_range(0.05, 0.2, 0.01) var ai_decision_interval: float = 0.1
## Spread NPC decisions across physics frames instead of creating one periodic spike.
@export var stagger_ai_planning: bool = true
