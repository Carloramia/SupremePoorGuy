# Spider generator integration

`Torso_Front` uses `front_torso`, `Torso_Rear` uses `rear_torso`, and `Head` uses `head`.
Fangs and the rivet remain unconnected.

Rear Torso uses FIT_UNIFORM to preserve the original visible art ratio (1490:963,
approximately 1.547:1). Its frame is 2.0 by 1.29261745 before generator scaling;
the final box collider uses that same frame size. The source sampled hull is
slightly shorter (about 2.0 by 1.288084) before the Spider box override.
Depth remains PartWidth. Its connection hole stays aligned to Front Torso.
The default density is unchanged, so the smaller volume reduces fitted mass.

The four legs on -Z use Left_1 through Left_4 in front-to-back order;
the four on +Z use Right_1 through Right_4. Leg_1..4 and Leg_5..8 follow this order.
Each `_Limb_1` uses UpperLeg and each terminal Leg uses LowerLeg.

Legacy calibrated variants are in `Bodyparts/Spider/Calibrated`, `Meshes/Spider/Calibrated`,
and `Creatures/Spider/Models/Calibrated`. They reference the original PNGs.
No original art or standalone Part is overwritten. Their mesh/UV deformation preserves
the end holes at approximately 0.1 units diameter, extends the shaft to a 2.0-unit
upper span / 2.8-unit lower span, and narrows the shaft to fit the existing frame.
Both connector spans then scale with the generator; depth remains PartWidth * OverallScale.
Changing upper and lower lengths independently can change their relative hole size.

The active leg rules now use `FrameFitted` variants. Sixteen new textures are stored
in `Assets/2DResources/Spider/FrameFitted/Limbs`, with matching `Models/FrameFitted`,
`Meshes/Spider/FrameFitted` and `Bodyparts/Spider/FrameFitted` resources. Their silhouette
matches the calibrated frame, but UV coordinates are linear in local XY. The central
texture repeats/reflections use the original local texel scale instead of stretching.
Joint neighborhoods retain isotropic source sampling and 0.1-unit hole diameters.
The short shaft/cap join uses a crossfade. Repetition can be visible on long shafts;
this is deterministic texture reconstruction, not AI repainting.
Each new Part inherits its calibrated Part and overrides only its mesh and art metadata;
collisions, transforms, connector markers and joints remain unchanged. Visual sides
are rebuilt from the new alpha silhouette. Three composite upper-leg sources use
only their white upper bar's two holes, excluding overlapping unrelated limbs.
The 0.1-unit diameter is before generator scaling. Texture density differs between
parts because original holes have different pixel diameters.

To rebuild the active variants, run `Tools/build_frame_fitted_textures.py` from this
asset folder, import the new PNGs in Godot, then run `res://Tools/BuildSpiderFrameFittedParts.gd`.
`Metadata/frame_fitted_manifest.json` records sources, texture densities and output paths.
`Tools/validate_frame_fitted_textures.py` checks original hashes and all 24 ring sizes/textures.
`res://Tests/ValidateSpiderFrameFittedParts.gd` checks the linear UV mapping and unchanged physics.

Front body roots use its two upper outer holes and two lower central holes.
The remaining lateral holes connect the rear body and head. The knee heights are
kept near the original stance, with a small bend adjustment to put the lower tips
on the ground while moving the roots onto the visible holes.

References live in the SpiderGenerator's Part Scene Rules and its species defaults,
and are inherited by Generate_Spider and Generate_Spider_NPC on regeneration.

Rebuild: run `Tools/calibrate_generator_parts.py` from this asset folder using Python
with Pillow/NumPy, followed by the Godot script `Tools/BuildSpiderCalibratedParts.gd`.
`Tools/ConnectSpiderParts.gd` reinstalls the 19 rules and the calibrated body markers.
`Tests/ValidateSpiderAssetConnections.gd` validates UV hole centers/diameters, joint
anchors, depth, structural reach, and repeated generation.
