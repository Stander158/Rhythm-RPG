"""Regenerate every sound effect in audio/ from scratch.

    python tools/make_audio.py

All game SFX are synthesized here — there are no recorded assets. Editing a
sound means editing its function below and re-running this script; Godot
re-imports the .wav on next open. (Music is NOT generated: tracks live in
user://music/, see README.)
"""
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parents[1] / "audio"


def write(name: str, samples, target: float | None = None) -> None:
    """Write mono 16-bit PCM. `target` normalizes the peak; None keeps levels."""
    if target is not None:
        peak = max(0.0001, max(abs(s) for s in samples))
        scale = min(1.0, target / peak) if target <= 1.0 else target / peak
        samples = [s * scale for s in samples]
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("wrote", path.name)


def mix(*layers):
    n = max(len(layer) for layer in layers)
    return [sum(layer[i] if i < len(layer) else 0.0 for layer in layers) for i in range(n)]


# ── Metronome / input ────────────────────────────────────────────────────

def click():
    n = int(SR * 0.06)
    return [0.5 * ((1 - i / n) ** 2) * math.sin(2 * math.pi * 880 * i / SR)
            for i in range(n)]


def press():
    n = int(SR * 0.045)
    return [0.3 * ((1 - i / n) ** 3) * math.sin(2 * math.pi * 700 * i / SR)
            for i in range(n)]


# ── Enemy cues ───────────────────────────────────────────────────────────

def charge():
    """Rising sweep: the enemy is winding up."""
    n = int(SR * 0.18)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * (300 + 400 * t) / SR
        out.append(0.45 * math.sin(math.pi * t) * math.sin(phase))
    return out


def attack():
    """Low thud with a noise crack."""
    n = int(SR * 0.15)
    out, phase = [], 0.0
    random.seed(1)
    for i in range(n):
        t = i / n
        env = (1 - t) ** 2
        phase += 2 * math.pi * (150 - 60 * t) / SR
        v = 0.8 * env * math.sin(phase)
        if i < SR * 0.03:
            v += 0.35 * env * (random.random() * 2 - 1)
        out.append(v)
    return out


def tick():
    """Piercing 'di' — the two-beat attack telegraph."""
    n = int(SR * 0.016)
    out = []
    for i in range(n):
        t = i / n
        env = (1 - t) ** 3
        v = math.sin(2 * math.pi * 5200 * i / SR)
        v += 0.6 * math.sin(2 * math.pi * 7800 * i / SR)
        v += 0.3 * math.sin(2 * math.pi * 10400 * i / SR)
        out.append(env * v)
    return out


def heavy_charge():
    """One long swelling drone for a heavy wind-up (cut short on release)."""
    n = int(SR * 3.0)
    out, ph1, ph2, prev = [], 0.0, 0.0, 0.0
    random.seed(9)
    for i in range(n):
        t = i / n
        swell = min(t * 3.0, 1.0) * (0.55 + 0.45 * t)
        f = 70 + 190 * (t ** 1.6)
        ph1 += 2 * math.pi * f / SR
        ph2 += 2 * math.pi * (f * 1.5) / SR
        trem = 0.85 + 0.15 * math.sin(2 * math.pi * (5 + 9 * t) * i / SR)
        prev += 0.02 * (random.uniform(-1, 1) - prev)
        out.append(swell * trem * (math.sin(ph1) + 0.45 * math.sin(ph2) + 1.2 * prev))
    return out


def stun():
    """Woozy chirp, repeated every two beats while an enemy is stunned."""
    n = int(SR * 0.5)
    out, ph = [], 0.0
    for i in range(n):
        t = i / n
        wob = math.sin(2 * math.pi * 7.0 * i / SR)
        f = (420 - 90 * t) * (1 + 0.18 * wob)
        ph += 2 * math.pi * f / SR
        env = min(i / (SR * 0.02), 1.0) * ((1 - t) ** 1.4)
        out.append(env * (math.sin(ph) + 0.3 * math.sin(ph * 2.02)))
    return out


# ── Battle stingers ──────────────────────────────────────────────────────

def explosion():
    n = int(SR * 0.8)
    out, ph, prev = [], 0.0, 0.0
    random.seed(5)
    for i in range(n):
        t = i / n
        env = (1 - t) ** 2.2
        prev += 0.06 * (random.uniform(-1, 1) - prev)
        ph += 2 * math.pi * (90 - 55 * t) / SR
        v = 0.9 * env * prev * 3.0 + 0.5 * env * math.sin(ph)
        if i < SR * 0.02:
            v += 0.6 * random.uniform(-1, 1)
        out.append(v)
    return out


def victory():
    notes = [(523.3, 0.14), (659.3, 0.14), (784.0, 0.14), (1046.5, 0.55)]
    total = int(SR * (sum(d for _, d in notes) + 0.2))
    out = [0.0] * total
    start = 0
    for f, d in notes:
        n = int(SR * (d + 0.15))
        for i in range(min(n, total - start)):
            t = i / n
            env = (1 - t) ** 1.8
            out[start + i] += 0.5 * env * math.sin(2 * math.pi * f * i / SR)
            out[start + i] += 0.2 * env * math.sin(2 * math.pi * f * 2 * i / SR)
        start += int(SR * d)
    return out


# ── Parry tiers ──────────────────────────────────────────────────────────

def _tone(dur, f, vol, decay=3.0):
    n = int(SR * dur)
    return [vol * ((1 - i / n) ** decay) * math.sin(2 * math.pi * f * i / SR)
            for i in range(n)]


def parry_swing():
    n = int(SR * 0.06)
    out, prev = [], 0.0
    random.seed(3)
    for i in range(n):
        t = i / n
        x = random.uniform(-1, 1)
        hp = x - prev
        prev = x
        out.append(0.3 * math.sin(math.pi * t) * hp)
    return out


# ── Spell casts (weak / normal / crit per spell) ─────────────────────────

def _noise(dur, vol, lp, decay=2.0):
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        env = (1 - i / n) ** decay
        prev += lp * (random.uniform(-1, 1) - prev)
        out.append(vol * env * prev)
    return out


def _sweep(dur, f0, f1, vol, decay=2.0):
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / n
        ph += 2 * math.pi * (f0 + (f1 - f0) * t) / SR
        out.append(vol * ((1 - t) ** decay) * math.sin(ph))
    return out


def _chime(freqs, note_dur, vol, tail=3.0, pad=0.12):
    total = int(SR * (note_dur * len(freqs) + pad))
    out = [0.0] * total
    for k, f in enumerate(freqs):
        start = int(SR * note_dur * k)
        n = total - start
        for i in range(n):
            t = i / n
            out[start + i] += vol * ((1 - t) ** tail) * math.sin(2 * math.pi * f * i / SR)
    return out


def _sparkle(dur, vol):
    n = int(SR * dur)
    out = [0.0] * n
    for _ in range(6):
        f = random.uniform(1400, 2600)
        start = random.randint(0, n // 2)
        m = min(int(SR * 0.06), n - start)
        for i in range(m):
            out[start + i] += vol * ((1 - i / m) ** 2) * math.sin(2 * math.pi * f * i / SR)
    return out


def _surge(dur, f0, f1, nvol, svol, lp):
    n = int(SR * dur)
    body, prev = [], 0.0
    for i in range(n):
        t = i / n
        prev += lp * (random.uniform(-1, 1) - prev)
        body.append(nvol * (math.sin(math.pi * t) ** 1.5) * prev)
    return mix(body, _sweep(dur, f0, f1, svol, decay=1.2))


def _zap(dur, vol, bright):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / n
        env = (1 - t) ** 1.5
        gate = 1.0 if math.sin(2 * math.pi * 90 * i / SR) > 0 else 0.2
        v = math.sin(2 * math.pi * (900 + bright * 300) * i / SR) * gate
        v += 0.4 * random.uniform(-1, 1) * gate
        out.append(vol * env * v)
    return out


def _stab(dur, f0, vol):
    n = int(SR * dur)
    out, ph = [], 0.0
    for i in range(n):
        t = i / n
        ph += 2 * math.pi * (f0 - (f0 - 400) * t) / SR
        v = ((1 - t) ** 4) * math.sin(ph)
        if i < SR * 0.008:
            v += 0.6 * random.uniform(-1, 1)
        out.append(vol * v)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    write("click", click())
    write("press", press())
    write("charge", charge())
    write("attack", attack())
    write("tick", tick(), 0.8)
    write("heavy_charge", heavy_charge(), 0.7)
    write("stun", stun(), 0.6)
    write("explosion", explosion(), 0.5)
    write("victory", victory(), 0.5)

    random.seed(3)
    write("parry_swing", parry_swing(), 0.45)
    write("parry_weak", mix(_tone(0.09, 180, 0.7, 2.0), _tone(0.09, 240, 0.3, 2.0)), 0.45)
    write("parry_normal", mix(_tone(0.15, 520, 0.6, 2.5), _tone(0.15, 780, 0.4, 3.0)), 0.45)
    write("parry_crit", mix(_tone(0.32, 1100, 0.55, 1.8), _tone(0.32, 1650, 0.35, 2.2),
                            _tone(0.32, 2200, 0.2, 2.6)), 0.45)

    random.seed(7)
    # Flame: fire bursts
    write("flame_weak", _noise(0.09, 0.5, 0.15), 0.45)
    write("flame_normal", mix(_noise(0.14, 0.7, 0.2), _sweep(0.12, 180, 70, 0.45)), 0.45)
    write("flame_crit", mix(_noise(0.22, 0.9, 0.3), _sweep(0.18, 240, 60, 0.55),
                            _sparkle(0.22, 0.25)), 0.45)
    # Cure: rising chimes
    write("cure_weak", _chime([440.0], 0.08, 0.5), 0.45)
    write("cure_normal", _chime([440.0, 554.4, 659.3], 0.06, 0.5), 0.45)
    write("cure_crit", _chime([523.3, 659.3, 784.0, 1046.5], 0.055, 0.55, tail=2.2), 0.45)
    # Wave: water surges
    write("wave_weak", _surge(0.13, 300, 150, 0.45, 0.3, 0.1), 0.45)
    write("wave_normal", _surge(0.2, 220, 90, 0.6, 0.4, 0.12), 0.45)
    write("wave_crit", mix(_surge(0.3, 260, 70, 0.8, 0.5, 0.15), _sparkle(0.3, 0.15)), 0.45)

    random.seed(11)
    # Bolt: electric zaps
    write("bolt_weak", _zap(0.10, 0.5, 0), 0.45)
    write("bolt_normal", _zap(0.16, 0.7, 1), 0.45)
    write("bolt_crit", _zap(0.26, 0.9, 2), 0.45)
    # Needle: sharp stabs
    write("needle_weak", _stab(0.05, 1200, 0.5), 0.45)
    write("needle_normal", _stab(0.07, 1400, 0.7), 0.45)
    write("needle_crit", _stab(0.1, 1700, 0.9), 0.45)
    # Attack+ : rising martial notes
    write("atkup_weak", _chime([330.0, 392.0], 0.07, 0.5, tail=2.5, pad=0.1), 0.45)
    write("atkup_normal", _chime([330.0, 415.3, 494.0], 0.06, 0.55, tail=2.5, pad=0.1), 0.45)
    write("atkup_crit", _chime([330.0, 415.3, 494.0, 659.3], 0.055, 0.6, tail=2.5, pad=0.1), 0.45)
    # Defense+ : falling, solid
    write("defup_weak", _chime([440.0, 349.2], 0.07, 0.5, tail=2.5, pad=0.1), 0.45)
    write("defup_normal", _chime([440.0, 349.2, 293.7], 0.06, 0.55, tail=2.5, pad=0.1), 0.45)
    write("defup_crit", mix(_chime([440.0, 349.2, 293.7, 220.0], 0.055, 0.6, tail=2.5, pad=0.1),
                            _chime([110.0], 0.3, 0.25, tail=1.5, pad=0.1)), 0.45)


if __name__ == "__main__":
    main()
