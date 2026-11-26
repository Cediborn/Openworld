#!/usr/bin/env python3
"""Synthesizes the water sounds (no recordings). Author: Claude (Openworld).

ambience/ (seamless loops, played in 3D along rivers and at falls):
  stream      a shallow stream over stones: bubbling, babbling, gurgles
  waterfall   a falling sheet into a pool: deep roar, hiss of spray
sfx/:
  splash      stepping or jumping into water
steps/:
  water_0..3  wading footsteps

Run from the repo root: python3 tools/audio/synth_water.py  (needs numpy, scipy, ffmpeg)
"""
import numpy as np

from synth_expansion import SR, bp, loopable, lp, noise, place, save, t

rng = np.random.default_rng(9090)


def bubble(f0, dur=0.06):
    """One small bubble: a quick rising sine blip (the sound of babbling water)."""
    tt = t(dur)
    f = f0 * (1.0 + tt / dur * 0.6)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 55)


def stream(d=24.0):
    x = bp(noise(d), 300, 3500) * 0.25 + lp(noise(d), 260) * 0.35
    for _ in range(int(d * 38)):
        place(x, bubble(rng.uniform(500, 1800), rng.uniform(0.03, 0.08)) * rng.uniform(0.15, 0.5), rng.uniform(0, d - 0.2))
    swell = 0.8 + 0.2 * np.sin(2 * np.pi * t(d) * 0.13)
    return loopable(x * swell, 1.5)


def waterfall(d=20.0):
    roar = lp(noise(d), 380) * 1.0 + bp(noise(d), 400, 1500) * 0.35
    hiss = bp(noise(d), 2500, 9000) * 0.22
    for _ in range(int(d * 25)):
        place(roar, bubble(rng.uniform(250, 700), 0.1) * rng.uniform(0.1, 0.3), rng.uniform(0, d - 0.2))
    return loopable(roar + hiss, 1.5)


def splash():
    d = 0.7
    tt = t(d)
    body = bp(noise(d), 350, 4000) * np.exp(-tt * 7)
    plop = np.sin(2 * np.pi * (180 + 300 * tt) * tt) * np.exp(-tt * 18) * 0.5
    x = body + plop
    for _ in range(14):
        place(x, bubble(rng.uniform(700, 2200), 0.05) * 0.25, rng.uniform(0.05, 0.5))
    return x


def wade(i):
    d = 0.4
    tt = t(d)
    r = np.random.default_rng(100 + i)
    x = bp(noise(d), 300 + 60 * i, 2600) * np.exp(-tt * 11) * 0.8
    for _ in range(6):
        place(x, bubble(r.uniform(400, 1300), 0.05) * 0.3, r.uniform(0.02, 0.25))
    return x


def main():
    save("ambience", "stream", stream(), q=3)
    save("ambience", "waterfall", waterfall(), q=3)
    save("sfx", "splash", splash(), peak=0.7)
    for i in range(4):
        save("steps", "water_%d" % i, wade(i), peak=0.6)


if __name__ == "__main__":
    main()
