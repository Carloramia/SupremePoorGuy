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


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind in DURATIONS:
        for variant in range(2):
            name = f"{kind}_{variant + 1:02}.wav"
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
