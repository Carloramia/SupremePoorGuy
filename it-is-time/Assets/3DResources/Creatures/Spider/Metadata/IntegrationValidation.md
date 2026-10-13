# Integration validation — 2026-10-10

Frame-fitted texture update:

- `validate_frame_fitted_textures.py`: PASS, 16 source hashes unchanged, 24 endpoint
  holes at 0.1-unit diameter and isotropic source ring sampling preserved.
- `ValidateSpiderFrameFittedParts`: PASS, 16 new PNG/mesh/Part references, linear
  texel scale, outward face winding and unchanged collision hulls/connector markers.
- `ValidateSpiderAssetConnections`: PASS again with the active FrameFitted rules,
  including saved character loading and two regenerations for both Spider and NPC.
- Saved character and generator/rule files match their pre-update contents after
  substituting only asset reference paths. Original/calibrated Parts are unchanged.
- Shaft texture is repeated/reflected at constant scale; visible pattern repetition
  remains possible. Three composite upper images use their white upper bar only.
  No new locomotion smoke test was run for this visual resource update.

Latest logs: SpiderFramePartsValidation.log and SpiderFrameConnectionsValidation.log
under D:/GameJamWorkspace. Overview: D:/GameJamWorkspace/SpiderFrameFittedPreview.png.

- ValidateSpiderAssetConnections: PASS. 24 working endpoint holes at approximately
  0.1 diameter, 19 scene mappings, 18 joints aligned in XY to actual authored markers,
  PartWidth depth, valid structural reach, identical loading and two regenerations
  for Generate_Spider and Generate_Spider_NPC.
- ValidateSpiderCharacters: PASS, including 1x/4x generation, axial springs, collision
  exceptions, eight-leg discovery, AI pursuit, enable switch and regeneration.
- ValidateWolfNPCLayoutSync: PASS; the optional connector-fit extension leaves Wolf
  geometry and repeated generation unchanged.
- SmokeSpiderStanding: standing height 1.1112 versus initial 1.1255; up alignment
  0.9999996. During the walking segment the torso moved about 38.04 along X and
  recorded six step failures/retries. The final turning segment reached up alignment
  0.7943 (about 37.4 degrees tilt), below that test's 0.8 threshold, so the full
  standing/walking/turning smoke test FAILED. Turning stability needs further tuning;
  the asset-integration checks alone do not establish stable high-speed locomotion.

Logs are in D:/GameJamWorkspace: ValidateSpiderAssetConnections.log,
SpiderConnectedCharactersFinal.log, WolfAfterSpiderConnections.log,
SpiderConnectedStanding.log. Godot also emits the pre-existing root certificate
store error in this environment.
