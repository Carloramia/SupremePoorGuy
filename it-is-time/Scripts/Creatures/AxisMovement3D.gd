@tool
extends RefCounted
## Input magnitude is retained; X and Z have independent world-axis speed targets.

static func target_velocity(direction: Vector3, x_speed: float, z_speed: float = 2.0) -> Vector3:
	if not direction.is_finite() or not is_finite(x_speed) or not is_finite(z_speed): return Vector3.ZERO
	var input := direction.slide(Vector3.UP).limit_length(1.0)
	return Vector3(input.x * maxf(x_speed, 0.0), 0.0, input.z * maxf(z_speed, 0.0))

static func braking_correction(velocity: Vector3, target: Vector3) -> Vector3:
	var correction := -velocity.slide(Vector3.UP)
	for axis: int in [0, 2]:
		if not is_zero_approx(target[axis]):
			correction[axis] = -signf(target[axis]) * maxf(velocity[axis] * signf(target[axis]) - absf(target[axis]), 0.0)
	return correction
