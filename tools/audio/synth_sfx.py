#!/usr/bin/env python3
"""Synthesizes the combat and reward sound effects (no recordings) and writes
them to game/assets/audio/sfx/:

  sword_swing_0..2  airy whooshes, one per combo swing
  sword_hit         blade biting into a creature
  block             steel-on-steel clang when a blow is blocked
  roll              cloth and footstep scuff of a dodge roll
  quest             rising chime for a new or finished quest
  discover          soft bell for a newly discovered place
  coins             a few clinking coins
  chest             wooden creak and thump of a chest lid
  potion            gulp and sparkle

Run from the repo root: python3 tools/audio/synth_sfx.py   (needs numpy and ffmpeg)
"""
import pathlib
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile

SR = 22050
OUT = pathlib.Path(__file__).resolve().parents[2] / "game" / "assets" / "audio" / "sfx"
rng = np.random.default_rng(31)


def t(d):
    return np.arange(int(d * SR)) / SR


def env(n, a, r):
    e = np.ones(n)
    ai = max(1, int(a * SR))
    ri = max(1, int(r * SR))
    e[:ai] = np.linspace(0, 1, ai)
    e[-ri:] *= np.linspace(1, 0, ri) ** 2
    return e


def bandnoise(d, lo, hi):
    x = rng.standard_normal(int(d * SR))
    f = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < lo) | (fr > hi)] = 0
    return np.fft.irfft(f, len(x))


def sweep_noise(d, f0, f1, q=0.25):
    """Noise through a band that slides from f0 to f1 (a whoosh)."""
    x = rng.standard_normal(int(d * SR))
    out = np.zeros_like(x)
    win = 512
    for i in range(0, len(x), win // 2):
        seg = x[i:i + win]
        if len(seg) < win:
            seg = np.pad(seg, (0, win - len(seg)))
        c = f0 + (f1 - f0) * (i / len(x))
        f = np.fft.rfft(seg * np.hanning(win))
        fr = np.fft.rfftfreq(win, 1 / SR)
        f *= np.exp(-((fr - c) / (c * q + 1)) ** 2)
        y = np.fft.irfft(f, win)
        out[i:i + win] += y[:len(out[i:i + win])]
    return out


def tone(d, f, decay, harm=(1.0,)):
    tt = t(d)
    x = sum(a * np.sin(2 * np.pi * f * (k + 1) * tt) for k, a in enumerate(harm))
    return x * np.exp(-tt * decay)


def norm(x, peak=0.85):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x, q=4):
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        wavfile.write(f.name, SR, (norm(x) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "libvorbis", "-q:a", str(q), str(OUT / (name + ".ogg"))], check=True)


def main():
    for i, (f0, f1, d) in enumerate([(500, 2600, 0.34), (2400, 600, 0.32), (300, 1800, 0.45)]):
        w = sweep_noise(d, f0, f1) * np.sin(np.linspace(0, np.pi, int(d * SR))) ** 1.5
        save("sword_swing_%d" % i, w)
    d = 0.35
    hit = bandnoise(d, 80, 900) * np.exp(-t(d) * 22) + 0.5 * tone(d, 140, 18) + 0.3 * bandnoise(d, 1500, 5000) * np.exp(-t(d) * 60)
    save("sword_hit", hit)
    d = 0.9
    clang = tone(d, 1180, 6, (1.0, 0.0, 0.5, 0.0, 0.3)) + 0.7 * tone(d, 1635, 7, (1.0, 0.3)) + 0.5 * bandnoise(d, 2000, 7000) * np.exp(-t(d) * 40)
    save("block", clang)
    d = 0.5
    roll = bandnoise(d, 150, 1500) * env(int(d * SR), 0.05, 0.25) + 0.6 * bandnoise(d, 60, 300) * np.exp(-((t(d) - 0.38) * 30) ** 2)
    save("roll", roll)
    notes = [523.25, 659.25, 783.99, 1046.5]
    q = np.zeros(int(1.6 * SR))
    for k, f in enumerate(notes):
        s = tone(1.2, f, 3.5, (1.0, 0.4, 0.15))
        o = int(k * 0.12 * SR)
        q[o:o + len(s)] += s
    save("quest", q)
    a = tone(2.2, 880, 2.2, (1.0, 0.0, 0.35, 0.0, 0.12))
    b = np.pad(tone(1.9, 1318.5, 2.5, (1.0, 0.2)), (int(0.3 * SR), 0))
    n = max(len(a), len(b))
    disc = np.pad(a, (0, n - len(a))) + 0.6 * np.pad(b, (0, n - len(b)))
    save("discover", disc)
    c = np.zeros(int(0.7 * SR))
    for k in range(5):
        s = tone(0.25, rng.uniform(2800, 4200), 25, (1.0, 0.5, 0.3)) * rng.uniform(0.5, 1.0)
        o = int(rng.uniform(0, 0.4) * SR)
        c[o:o + len(s)] += s[:len(c) - o]
    save("coins", c)
    d = 0.8
    creak = np.sin(2 * np.pi * (180 + 60 * np.sin(t(d) * 9)) * t(d)) * bandnoise(d, 100, 2000) * env(int(d * SR), 0.05, 0.3) * 0.6
    thump = np.zeros(int(d * SR))
    th = tone(0.3, 90, 20) + 0.5 * bandnoise(0.3, 50, 400) * np.exp(-t(0.3) * 25)
    o = int(0.5 * SR)
    thump[o:o + len(th)] += th[:len(thump) - o]
    save("chest", creak + thump)
    d = 0.9
    gulp = np.zeros(int(d * SR))
    for k in range(3):
        s = tone(0.12, 220 + 40 * k, 30)
        o = int(k * 0.15 * SR)
        gulp[o:o + len(s)] += s
    sparkle = 0.4 * bandnoise(d, 4000, 9000) * np.exp(-((t(d) - 0.65) * 8) ** 2)
    save("potion", gulp + sparkle)
    print("wrote", sorted(p.name for p in OUT.glob("*.ogg")))


if __name__ == "__main__":
    main()
