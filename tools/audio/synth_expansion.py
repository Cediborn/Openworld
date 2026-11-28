#!/usr/bin/env python3
"""Synthesizes the sounds added with the firearm, horse whistle, buildings,
tavern and church (no recordings, no downloads). Author: Claude (Openworld).

sfx/ (game/assets/audio/sfx):
  shotgun_shot      sharp muzzle crack, heavy low boom, echo off the hills
  shotgun_pump      fore-end racked back and forward: two metal clacks and a slide
  shotgun_shell     one shell thumbed into the magazine tube
  shotgun_click     dry trigger click on an empty chamber
  whistle           two-finger whistle, rising then falling
  horse_whinny      a horse answering from a distance
  door              heavy wooden door: latch, creak, thud
  church_bell       one stroke of a large bronze bell (inharmonic partials)
  bed               straw mattress and blanket rustle

ambience/ (game/assets/audio/ambience), seamless loops:
  tavern            murmur of voices, cups, a crackling fire
  church            hushed nave: air, distant footsteps, a cough, candle hiss
  fire              hearth crackle (fireplaces, forge)

Run from the repo root: python3 tools/audio/synth_expansion.py [name ...]  (needs numpy, scipy, ffmpeg)
With names, only those sounds are written (each sound has its own random seed,
so rebuilding one never changes another).
"""
import pathlib
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 22050
ROOT = pathlib.Path(__file__).resolve().parents[2] / "game" / "assets" / "audio"
rng = np.random.default_rng(1717)


def t(d):
    return np.arange(int(d * SR)) / SR


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype="band")
    return lfilter(b, a, x)


def lp(x, hi, order=2):
    b, a = butter(order, hi / (SR / 2), btype="low")
    return lfilter(b, a, x)


def noise(d):
    return rng.standard_normal(int(d * SR))


def norm(x, peak=0.85):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def place(buf, snd, at):
    o = int(at * SR)
    n = min(len(snd), len(buf) - o)
    if n > 0:
        buf[o:o + n] += snd[:n]


def save(folder, name, x, q=4, peak=0.85):
    out = ROOT / folder
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav") as f:
        wavfile.write(f.name, SR, (norm(x, peak) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "libvorbis", "-q:a", str(q), str(out / (name + ".ogg"))], check=True)


def loopable(x, fade=1.0):
    """Crossfade the tail into the head so the loop has no seam."""
    n = int(fade * SR)
    head = x[:n].copy()
    tail = x[-n:]
    w = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x


def crackle(d, rate, loud=1.0):
    x = np.zeros(int(d * SR))
    for _ in range(int(d * rate)):
        L = rng.uniform(0.002, 0.012)
        pop = bp(noise(L), 1200, 7000) * np.exp(-t(L) * rng.uniform(300, 900))
        place(x, pop * rng.uniform(0.2, 1.0) * loud, rng.uniform(0, d - 0.02))
    return x


def shotgun_shot():
    d = 2.4
    x = np.zeros(int(d * SR))
    # A hard, wide crack (many pellets and a big powder charge) ...
    crack = bp(noise(0.06), 600, 9500) * np.exp(-t(0.06) * 75) * 1.4
    # ... a heavy chest-thump boom, lower and longer than a pistol ...
    boom = lp(noise(1.0), 320) * np.exp(-t(1.0) * 5.5) * 3.4 + np.sin(2 * np.pi * 46 * t(1.0)) * np.exp(-t(1.0) * 7) * 1.1
    place(x, crack, 0.0)
    place(x, boom, 0.0)
    # ... and the rolling echo off the hills.
    for k, (delay, g) in enumerate([(0.29, 0.3), (0.58, 0.18), (0.9, 0.1)]):
        place(x, lp(boom, 520 - k * 110) * g, delay)
    return x


def _clack(d, lo, hi, decay, ring_hz, ring=0.35):
    """Steel on steel: a band of noise and a short metallic ring."""
    return bp(noise(d), lo, hi) * np.exp(-t(d) * decay) + ring * np.sin(2 * np.pi * ring_hz * t(d)) * np.exp(-t(d) * decay * 1.4)


def shotgun_pump():
    d = 0.55
    x = np.zeros(int(d * SR))
    slide = bp(noise(0.09), 1500, 6000) * np.sin(np.linspace(0, np.pi, int(0.09 * SR))) * 0.25
    place(x, slide, 0.02)                                       # fore-end slides back
    place(x, _clack(0.06, 900, 7000, 90, 2300) * 0.9, 0.1)      # bolt hits the rear
    place(x, bp(noise(0.03), 2500, 9000) * np.exp(-t(0.03) * 160) * 0.3, 0.13)   # spent shell flicks out
    place(x, slide * 0.9, 0.2)                                  # forward again
    place(x, _clack(0.07, 700, 6000, 80, 1800), 0.28)           # locks into battery
    return x


def shotgun_shell():
    d = 0.3
    x = np.zeros(int(d * SR))
    place(x, bp(noise(0.04), 1200, 5000) * np.exp(-t(0.04) * 90) * 0.4, 0.0)   # brass rim on the loading gate
    place(x, _clack(0.05, 800, 5000, 110, 1500, 0.25) * 0.7, 0.07)            # pushed home past the spring
    return x


def shotgun_click():
    d = 0.25
    x = np.zeros(int(d * SR))
    place(x, _clack(0.03, 2000, 9000, 180, 3100, 0.2), 0.0)
    return x


def whistle():
    d = 1.1
    tt = t(d)
    f = 1900 + 700 * np.sin(np.clip(tt / 0.45, 0, 1) * np.pi / 2) - 900 * np.clip((tt - 0.55) / 0.5, 0, 1) ** 1.5
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.clip(tt / 0.04, 0, 1) * np.clip((d - tt) / 0.12, 0, 1) * (0.8 + 0.2 * np.sin(tt * 37))
    body = np.sin(ph) + 0.15 * np.sin(2 * ph)
    breath = bp(noise(d), 1500, 5000) * 0.12
    return (body + breath) * env


def horse_whinny():
    d = 1.6
    tt = t(d)
    f = 620 + 280 * np.sin(np.pi * np.clip(tt / 0.7, 0, 1)) - 260 * np.clip((tt - 0.7) / 0.9, 0, 1)
    vib = 1 + 0.06 * np.sin(2 * np.pi * 14 * tt) * np.clip(tt / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    voice = sum(a * np.sin(k * ph) for k, a in [(1, 1.0), (2, 0.6), (3, 0.35), (4, 0.2)])
    env = np.clip(tt / 0.05, 0, 1) * np.clip((d - tt) / 0.5, 0, 1)
    snort = bp(noise(d), 300, 2500) * 0.25
    x = (voice + snort) * env
    return lp(x, 3500) * 0.8   # heard from a distance


def door():
    d = 1.3
    x = np.zeros(int(d * SR))
    place(x, bp(noise(0.04), 1500, 6000) * np.exp(-t(0.04) * 120), 0.0)   # latch
    tt = t(0.7)
    creak = np.sin(2 * np.pi * np.cumsum(260 + 120 * np.sin(tt * 7) + 60 * rng.standard_normal(len(tt)) * 0.1) / SR)
    creak *= bp(noise(0.7), 200, 2500) * 0.6 + 0.4
    place(x, creak * np.sin(np.linspace(0, np.pi, len(tt))) * 0.35, 0.08)
    place(x, lp(noise(0.3), 300) * np.exp(-t(0.3) * 18) * 1.5 + np.sin(2 * np.pi * 70 * t(0.3)) * np.exp(-t(0.3) * 20), 0.85)   # thud
    return x


def church_bell():
    d = 6.0
    tt = t(d)
    f0 = 196.0   # G3
    partials = [(0.5, 0.6, 0.7), (1.0, 1.0, 1.1), (1.19, 0.7, 1.4), (1.5, 0.5, 1.7), (2.0, 0.6, 2.0), (2.52, 0.3, 2.6), (2.66, 0.25, 2.8), (3.36, 0.2, 3.3)]
    x = sum(a * np.sin(2 * np.pi * f0 * r * tt + rng.uniform(0, 6)) * np.exp(-tt * dec * 0.6) for r, a, dec in partials)
    strike = bp(noise(0.05), 800, 5000) * np.exp(-t(0.05) * 80)
    out = np.zeros(len(tt))
    place(out, x, 0.0)
    place(out, strike * 0.6, 0.0)
    return out * np.clip(tt / 0.005, 0, 1)


def bed():
    d = 1.4
    return bp(noise(d), 400, 4000) * (0.4 + 0.6 * np.abs(np.sin(np.linspace(0, 3.5 * np.pi, int(d * SR))))) * np.exp(-t(d) * 1.2)


def tavern(d=32.0):
    x = np.zeros(int(d * SR))
    # Many overlapping voices: formant-filtered noise with syllable rhythm.
    for v in range(9):
        f0 = rng.uniform(95, 230)
        tt = t(d)
        ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.08 * np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * tt))) / SR
        glott = sum(np.sin(k * ph) / k for k in range(1, 12))
        syl = (np.sin(2 * np.pi * rng.uniform(3.0, 5.5) * tt + rng.uniform(0, 6)) > 0.1).astype(float)
        phrase = (np.sin(2 * np.pi * rng.uniform(0.08, 0.2) * tt + rng.uniform(0, 6)) > -0.2).astype(float)
        env = lp(syl * phrase, 18)
        voice = bp(glott, 300, 2600) * env
        x += voice * rng.uniform(0.15, 0.4)
    x = lp(x, 2400) + bp(noise(d), 200, 1200) * 0.05
    for _ in range(int(d * 0.5)):    # cups and plates
        L = 0.3
        clink = np.sin(2 * np.pi * rng.uniform(1800, 3200) * t(L)) * np.exp(-t(L) * 30) + 0.5 * bp(noise(L), 2000, 6000) * np.exp(-t(L) * 60)
        place(x, clink * rng.uniform(0.05, 0.15), rng.uniform(0, d - L))
    x += crackle(d, 14, 0.25)
    return loopable(x)


def church(d=32.0):
    x = bp(noise(d), 80, 500) * 0.08                       # large-room air
    for _ in range(int(d * 0.4)):                          # distant footsteps on stone
        L = 0.12
        st = bp(noise(L), 300, 2500) * np.exp(-t(L) * 50)
        at = rng.uniform(0, d - 3)
        for k in range(rng.integers(3, 7)):
            place(x, st * 0.25 * rng.uniform(0.6, 1.0), at + k * 0.55)
    for _ in range(2):                                     # a cough, a creaking pew
        place(x, bp(noise(0.25), 300, 2000) * np.exp(-t(0.25) * 12) * 0.3, rng.uniform(0, d - 1))
        tt = t(0.5)
        place(x, np.sin(2 * np.pi * np.cumsum(330 + 80 * np.sin(tt * 11)) / SR) * bp(noise(0.5), 300, 1500) * 0.15 * np.sin(np.linspace(0, np.pi, len(tt))), rng.uniform(0, d - 1))
    # Reverb: a few long, dark echoes.
    wet = np.zeros_like(x)
    for delay, g in [(0.09, 0.5), (0.21, 0.4), (0.37, 0.3), (0.61, 0.22), (0.9, 0.15)]:
        o = int(delay * SR)
        wet[o:] += lp(x[:-o], 1800) * g
    return loopable(x + wet)


def fire(d=24.0):
    x = lp(noise(d), 300) * 0.15 + bp(noise(d), 300, 1200) * 0.05 * (1 + 0.5 * np.sin(2 * np.pi * 0.3 * t(d)))
    x += crackle(d, 30, 1.0)
    return loopable(x)


SOUNDS = {
    "shotgun_shot": ("sfx", shotgun_shot, {"peak": 0.97}),
    "shotgun_pump": ("sfx", shotgun_pump, {}),
    "shotgun_shell": ("sfx", shotgun_shell, {}),
    "shotgun_click": ("sfx", shotgun_click, {}),
}


def main():
    import sys
    global rng
    for name, (folder, fn, kw) in SOUNDS.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        rng = np.random.default_rng(sum(map(ord, name)) * 7919)   # stable per sound
        save(folder, name, fn(), **kw)
    if len(sys.argv) > 1:
        return
    rng = np.random.default_rng(1717)
    save("sfx", "whistle", whistle())
    save("sfx", "horse_whinny", horse_whinny())
    save("sfx", "door", door())
    save("sfx", "church_bell", church_bell())
    save("sfx", "bed", bed())
    save("ambience", "tavern", tavern(), q=3)
    save("ambience", "church", church(), q=3)
    save("ambience", "fire", fire(), q=3)
    print("wrote expansion sounds")


if __name__ == "__main__":
    main()
