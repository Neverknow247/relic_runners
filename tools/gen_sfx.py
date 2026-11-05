"""Procedural placeholder SFX for Relic Runners (stdlib only).

Run from the project root:  python tools/gen_sfx.py
Writes 16-bit mono WAVs into assets/audio/sounds/sfx_*.wav. These are first-pass
placeholders so combat isn't silent; swap any file for a real asset with the same
name and nothing else needs to change (see singletons/sounds.gd SFX table).
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join("assets", "audio", "sounds")
random.seed(1234)  # deterministic output, so re-running doesn't churn git


def env(t, dur, attack=0.005, curve=3.0):
    """Fast attack, exponential-ish decay to 0 at dur."""
    if t < attack:
        return t / attack
    x = (t - attack) / max(dur - attack, 1e-6)
    return max(0.0, (1.0 - x)) ** curve


def sweep(f0, f1, t, dur):
    """Instantaneous frequency of an exponential sweep f0 -> f1."""
    k = t / dur
    return f0 * (f1 / f0) ** k


class Synth:
    def __init__(self, dur):
        self.n = int(RATE * dur)
        self.buf = [0.0] * self.n
        self.dur = dur

    def tone(self, f0, f1, amp, wave_kind="sine", start=0.0, dur=None, attack=0.005, curve=3.0):
        dur = dur if dur is not None else self.dur - start
        s0 = int(start * RATE)
        n = int(dur * RATE)
        phase = 0.0
        for i in range(n):
            t = i / RATE
            f = sweep(f0, f1, t, dur)
            phase += 2 * math.pi * f / RATE
            if wave_kind == "sine":
                v = math.sin(phase)
            elif wave_kind == "square":
                v = 1.0 if math.sin(phase) >= 0 else -1.0
            elif wave_kind == "saw":
                v = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
            else:  # triangle
                v = 2.0 * abs(2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0) - 1.0
            j = s0 + i
            if j < self.n:
                self.buf[j] += v * amp * env(t, dur, attack, curve)

    def noise(self, amp, start=0.0, dur=None, smooth=0.0, attack=0.002, curve=3.0, swell=False):
        """White noise; smooth in [0,1) low-passes it (higher = darker)."""
        dur = dur if dur is not None else self.dur - start
        s0 = int(start * RATE)
        n = int(dur * RATE)
        last = 0.0
        for i in range(n):
            t = i / RATE
            r = random.uniform(-1.0, 1.0)
            last = last * smooth + r * (1.0 - smooth)
            e = math.sin(math.pi * t / dur) if swell else env(t, dur, attack, curve)
            j = s0 + i
            if j < self.n:
                self.buf[j] += last * amp * e

    def write(self, name):
        peak = max(1e-6, max(abs(v) for v in self.buf))
        gain = min(1.0, 0.9 / peak)
        path = os.path.join(OUT, "sfx_%s.wav" % name)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * gain)) * 32767)) for v in self.buf))
        print("wrote", path)


def main():
    os.makedirs(OUT, exist_ok=True)

    s = Synth(0.07); s.tone(1400, 700, 0.5, "square", curve=2.0); s.noise(0.15, dur=0.02); s.write("shoot_wand")
    s = Synth(0.16); s.tone(260, 70, 0.8, "sine", curve=2.0); s.noise(0.35, dur=0.05, smooth=0.6); s.write("shoot_orb")
    s = Synth(0.12); s.noise(0.6, smooth=0.3, curve=2.5); s.tone(620, 380, 0.3, "triangle"); s.write("shoot_tome")
    s = Synth(0.09); s.tone(520, 300, 0.35, "triangle", curve=2.0); s.noise(0.2, dur=0.03, smooth=0.5); s.write("enemy_shoot")
    s = Synth(0.05); s.noise(0.7, smooth=0.1, curve=4.0); s.tone(900, 500, 0.3, "sine"); s.write("hit")
    s = Synth(0.38)
    s.noise(0.5, smooth=0.2, curve=2.0)
    for k, f in enumerate([2400, 1900, 3100, 1600]):
        s.tone(f, f * 0.7, 0.18, "sine", start=0.01 + k * 0.03, dur=0.3 - k * 0.04, curve=4.0)
    s.write("enemy_die")
    s = Synth(0.24); s.tone(180, 60, 0.9, "sine", curve=2.0); s.noise(0.5, dur=0.12, smooth=0.5); s.write("player_hurt")
    s = Synth(0.25); s.noise(0.6, smooth=0.85, swell=True); s.write("roll")
    s = Synth(0.035); s.tone(1250, 1250, 0.4, "sine", curve=4.0); s.write("tap")
    s = Synth(0.3)
    for k, f in enumerate([660, 880, 1320]):
        s.tone(f, f, 0.3, "triangle", start=k * 0.07, dur=0.16, curve=2.5)
    s.write("armed")
    s = Synth(0.2); s.tone(220, 110, 0.35, "saw", curve=1.5); s.write("fizzle")
    s = Synth(0.5); s.tone(300, 900, 0.35, "sine", attack=0.4, curve=0.6); s.write("windup")
    s = Synth(0.7); s.tone(700, 1800, 0.3, "sine", attack=0.6, curve=0.5); s.tone(1400, 3600, 0.08, "square", attack=0.6, curve=0.5); s.write("sniper_windup")
    s = Synth(0.45); s.tone(140, 45, 0.7, "sine", curve=1.5); s.noise(0.5, smooth=0.75, curve=1.5); s.tone(500, 1500, 0.15, "triangle", dur=0.2); s.write("spell_cast")
    s = Synth(0.6); s.noise(0.9, smooth=0.9, curve=1.8); s.tone(90, 35, 0.8, "sine", curve=1.5); s.write("explosion")
    s = Synth(0.2); s.noise(0.6, smooth=0.8, curve=2.0); s.tone(160, 80, 0.6, "sine", curve=2.0); s.write("shove")
    s = Synth(0.35); s.tone(988, 988, 0.3, "sine", dur=0.15); s.tone(1319, 1319, 0.3, "sine", start=0.1, dur=0.25); s.write("loot")
    s = Synth(0.03); s.tone(1800, 1200, 0.3, "square", curve=4.0); s.write("ui_click")


if __name__ == "__main__":
    main()
