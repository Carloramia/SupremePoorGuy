"""Regenerate the project's procedural placeholder SFX (Python standard library only)."""
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Assets/Audio/SFX/Combat"
RATE = 44100
DURATIONS = {"attack": 0.24, "bite": 0.20, "charge": 0.48,
             "stomp": 0.58, "hit": 0.18, "break": 0.32, "bow": 0.28}
BLADE_DURATIONS = {"blade_swing": 0.32, "blade_hit": 0.29,
                   "blade_clash": 0.38}
BLADE_VARIANTS = {"blade_swing": 3, "blade_hit": 2, "blade_clash": 2}
CRISP_HIT_DURATION = 0.16
CRISP_HIT_VARIANTS = 4


def synthesize(kind, variant):
    rng = random.Random(20261018 + list(DURATIONS).index(kind) * 17 + variant)
    duration = DURATIONS[kind]
    count = round(duration * RATE)
    samples = []
    low = 0.0
    phase = 0.0
    tone = 0.95 + variant * 0.08
    for index in range(count):
        t = index / RATE
        progress = t / duration
        noise = rng.uniform(-1.0, 1.0)
        low += 0.12 * (noise - low)
        high = noise - low
        if kind == "attack":
            envelope = math.sin(math.pi * progress) ** 1.7
            phase += math.tau * (850.0 - 620.0 * progress) * tone / RATE
            value = (high * 0.55 + math.sin(phase) * 0.08) * envelope
        elif kind == "charge":
            envelope = math.sin(math.pi * progress) ** 0.8
            value = (low * 1.6 + high * 0.12 + math.sin(math.tau * 62 * tone * t) * 0.2) * envelope
        elif kind == "stomp":
            phase += math.tau * (38 + 55 * math.exp(-t * 24)) * tone / RATE
            value = math.sin(phase) * math.exp(-t * 9) + low * math.exp(-t * 13) * 1.8
            value += high * math.exp(-t * 65) * 0.25
        elif kind == "hit":
            phase += math.tau * (95 + 130 * math.exp(-t * 45)) * tone / RATE
            value = math.sin(phase) * math.exp(-t * 25) + low * math.exp(-t * 32) * 1.4
            value += high * math.exp(-t * 80) * 0.25
        elif kind in ("bite", "break"):
            value = math.sin(math.tau * 125 * tone * t) * math.exp(-t * 32) * 0.3
            # Separate short cracks rather than a sustained hiss.
            for onset, strength in [(0.0, 1.0), (0.028, 0.65), (0.065, 0.4), (0.12, 0.22)]:
                elapsed = t - onset
                if elapsed >= 0:
                    value += (high if kind == "break" else low * 2.0 + high * 0.2) * math.exp(-elapsed * 95) * strength
        else:  # Bow: string pluck with a short air transient.
            value = (math.sin(math.tau * 185 * tone * t) + math.sin(math.tau * 370 * tone * t) * 0.35) * math.exp(-t * 22)
            value += high * math.exp(-t * 40) * 0.3
        fade = min(1.0, t / 0.003, (duration - t) / 0.012)
        samples.append(value * max(0.0, fade))
    peak = max(abs(value) for value in samples)
    result = array("h", (round(value / peak * 0.62 * 32767) for value in samples))
    result[0] = result[-1] = 0
    return result


def synthesize_blade(kind, variant):
    """Soft edged weapon layers: moving air, low impact, and damped steel."""
    rng = random.Random(20261019 + list(BLADE_DURATIONS).index(kind) * 31 + variant)
    duration = BLADE_DURATIONS[kind]
    count = round(duration * RATE)
    samples = []
    fast = slow = mellow = phase = 0.0
    pitch = 1.0 + (variant - 1) * 0.075
    for index in range(count):
        t = index / RATE
        progress = t / duration
        noise = rng.uniform(-1.0, 1.0)
        # Two gentle one-pole filters make a broad, low-mid air band.
        fast += 0.19 * (noise - fast)
        slow += 0.018 * (noise - slow)
        mellow += 0.10 * (fast - slow - mellow)
        air = mellow
        if kind == "blade_swing":
            center = 0.43 + variant * 0.035
            sweep = math.exp(-((progress - center) / 0.23) ** 2)
            phase += math.tau * (245 - 115 * progress) * pitch / RATE
            value = air * sweep * 2.2 + math.sin(phase) * sweep * 0.10
            value += math.sin(math.tau * (580 - 200 * progress) * pitch * t) * sweep * 0.035
        else:
            onset = 0.016 if kind == "blade_hit" else 0.009
            elapsed = max(0.0, t - onset)
            gate = min(1.0, max(0.0, (t - onset) / 0.004))
            body_decay = 17 if kind == "blade_hit" else 13
            phase += math.tau * (85 + 120 * math.exp(-elapsed * 32)) * pitch / RATE
            body = math.sin(phase) * math.exp(-elapsed * body_decay)
            soft_crack = air * math.exp(-elapsed * 52) * 1.5
            # A few damped partials suggest steel without a piercing high ring.
            ring = (math.sin(math.tau * 520 * pitch * elapsed) * 0.20
                    + math.sin(math.tau * 815 * pitch * elapsed) * 0.12
                    + math.sin(math.tau * 1260 * pitch * elapsed) * 0.045)
            ring *= math.exp(-elapsed * (24 if kind == "blade_hit" else 15))
            value = gate * (body * (0.48 if kind == "blade_hit" else 0.32)
                            + soft_crack + ring)
        fade = min(1.0, t / 0.005, (duration - t) / 0.025)
        samples.append(value * max(0.0, fade))
    peak = max(abs(value) for value in samples)
    result = array("h", (round(value / peak * 0.60 * 32767) for value in samples))
    result[0] = result[-1] = 0
    return result


def synthesize_crisp_hit(variant):
    """Immediate contact snap with a short body and no lingering ring."""
    rng = random.Random(20261020 + variant)
    count = round(CRISP_HIT_DURATION * RATE)
    samples = []
    fast = slow = softened = phase = 0.0
    pitch = 0.94 + variant * 0.055
    strength = 0.26 if variant < 2 else 0.40
    for index in range(count):
        t = index / RATE
        noise = rng.uniform(-1.0, 1.0)
        fast += 0.33 * (noise - fast)
        slow += 0.035 * (noise - slow)
        softened += 0.18 * (fast - slow - softened)
        snap = softened * math.exp(-t * (76 + variant * 3)) * 2.5
        phase += math.tau * (115 + 165 * math.exp(-t * 48)) * pitch / RATE
        body = math.sin(phase) * math.exp(-t * 43) * strength
        tick = (math.sin(math.tau * 1350 * pitch * t) * 0.14
                + math.sin(math.tau * 2100 * pitch * t) * 0.07)
        tick *= math.exp(-t * 90)
        fade = min(1.0, t / 0.0012, (CRISP_HIT_DURATION - t) / 0.009)
        samples.append((snap + body + tick) * max(0.0, fade))
    peak = max(abs(value) for value in samples)
    result = array("h", (round(value / peak * 0.62 * 32767) for value in samples))
    result[0] = result[-1] = 0
    return result


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind in (*DURATIONS, *BLADE_DURATIONS, "hit_crisp"):
        for variant in range(CRISP_HIT_VARIANTS if kind == "hit_crisp" else BLADE_VARIANTS.get(kind, 2)):
            name = f"{kind}_{variant + 1:02}.wav"
            if kind == "hit_crisp":
                samples = synthesize_crisp_hit(variant)
            elif kind in BLADE_DURATIONS:
                samples = synthesize_blade(kind, variant)
            else:
                samples = synthesize(kind, variant)
            assert max(abs(value) for value in samples) < 32767
            assert samples[0] == samples[-1] == 0
            rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
            if sys.byteorder != "little":
                samples.byteswap()
            path = OUT / name
            with wave.open(str(path), "wb") as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(RATE)
                output.writeframes(samples.tobytes())
            entries.append({"file": name, "event": kind, "duration": len(samples) / RATE,
                            "rms_dbfs": round(20 * math.log10(rms), 2),
                            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {"source": "Procedural synthesis; no external recordings or samples",
                "generator": "res://Tools/Audio/generate_combat_sfx.py", "sample_rate": RATE,
                "channels": 1, "bits_per_sample": 16, "files": entries}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"COMBAT_SFX_GENERATED={len(entries)}")


if __name__ == "__main__":
    main()
