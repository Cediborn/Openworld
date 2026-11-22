#!/usr/bin/env python3
"""Synthesizes every game sound from scratch (no recordings, no downloads) and
writes them as .ogg files to game/assets/audio/.

Author: Claude (Openworld). Run from the repo root:
    python3 tools/audio/synth_sounds.py

* ambience/  seamless 32 s loops per biome (meadow birds and wind, frost
             gale, ember rumble and crackle, glow-hollow shimmer and crickets,
             village with distant hammering)
* steps/     footsteps on grass, stone and snow (several takes each), jump, land
* creatures/ calls and roars for every species in data/creatures.json

Needs numpy, scipy and ffmpeg with libvorbis.
"""
import pathlib
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
OUT = pathlib.Path(__file__).resolve().parents[2] / "game" / "assets" / "audio"
rng = np.random.default_rng(7)

# ---------------------------------------------------------------- building blocks

def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def noise(dur):
    return rng.standard_normal(int(round(dur * SR)))


def pink(dur):
    """1/f noise via Paul Kellet's filter."""
    w = noise(dur)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w) * 4


def brown(dur):
    x = np.cumsum(noise(dur)) * 0.02
    return x - signal.lfilter([1], [1, -0.995], x) * 0.005 - np.mean(x)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "lowpass", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "highpass", fs=SR, output="sos"), x)


def env(n, attack, release, shape=2.0):
    """Attack/release envelope over n samples (times in seconds)."""
    e = np.ones(n)
    a, r = max(int(attack * SR), 1), max(int(release * SR), 1)
    e[:a] = np.linspace(0, 1, a) ** shape
    e[-r:] = np.minimum(e[-r:], np.linspace(1, 0, r) ** shape)
    return e


def osc(freq_curve, kind="sine"):
    """Oscillator following a per-sample frequency curve."""
    ph = 2 * np.pi * np.cumsum(freq_curve) / SR
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    if kind == "pulse":
        return np.sign(np.sin(ph)) * 0.7
    return np.sin(ph)


def formants(x, freqs, bw=1.6):
    """Vocal-tract colour: sum of band-passes around each formant frequency."""
    y = np.zeros_like(x)
    for i, f in enumerate(freqs):
        y += bp(x, f / bw ** 0.5, min(f * bw ** 0.5, SR / 2 - 100)) / (i + 1)
    return y


def reverb(x, wet=0.3, size=1.0):
    """Small Schroeder reverb: 4 combs + 2 all-passes."""
    out = np.zeros(len(x) + int(SR * 1.5 * size))
    xp = np.concatenate([x, np.zeros(len(out) - len(x))])
    for d, g in ((1557, 0.84), (1617, 0.83), (1491, 0.82), (1422, 0.81)):
        d = int(d * size)
        a = np.zeros(d + 1)
        a[0], a[-1] = 1, -g
        out += signal.lfilter([1], a, xp)
    for d, g in ((225, 0.5), (556, 0.5)):
        b = np.zeros(d + 1)
        b[0], b[-1] = -g, 1
        a = np.zeros(d + 1)
        a[0], a[-1] = 1, -g
        out = signal.lfilter(b, a, out)
    return xp * (1 - wet) + out / 4 * wet


def place(buf, clip, at):
    i = int(at * SR)
    j = min(len(buf), i + len(clip))
    if i < len(buf):
        buf[i:j] += clip[: j - i]


def norm(x, peak=0.9):
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def loopify(x, fade=2.0):
    """Crossfades the tail into the head so the clip loops without a click."""
    n = int(fade * SR)
    head, tail = x[:n], x[-n:]
    w = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x


def save(rel, x, quality=3):
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wavfile.write(f.name, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", f.name, "-c:a", "libvorbis", "-q:a", str(quality), str(path)], check=True)
    print(f"{rel}: {len(x) / SR:.1f}s")

# ---------------------------------------------------------------- ambience

def wind(dur, lo, hi, gust=0.25, rate=0.07):
    w = bp(pink(dur), lo, hi)
    t = t_axis(dur)
    slow = 0.6 + gust * np.sin(2 * np.pi * rate * t + rng.random() * 6) + gust * 0.6 * np.sin(2 * np.pi * rate * 2.7 * t)
    return w * slow


def bird_chirp():
    """One songbird phrase: a few rising/falling whistles with warble."""
    clip = np.zeros(0)
    base = rng.uniform(2600, 4200)
    for k in range(rng.integers(2, 6)):
        d = rng.uniform(0.05, 0.16)
        t = t_axis(d)
        sweep = base * (1 + rng.uniform(-0.25, 0.35) * t / d) * (1 + 0.04 * np.sin(2 * np.pi * rng.uniform(25, 60) * t))
        tone = osc(sweep) + 0.25 * osc(sweep * 2)
        clip = np.concatenate([clip, tone * env(len(t), 0.01, 0.03), np.zeros(int(rng.uniform(0.02, 0.09) * SR))])
    return clip


def amb_meadow():
    dur = 34.0
    x = wind(dur, 150, 1200, 0.3) * 0.5
    leaves = bp(noise(dur), 2500, 7000) * 0.03 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.11 * t_axis(dur)) ** 2)
    x += leaves
    birds = np.zeros_like(x)
    at = 0.5
    while at < dur - 2:
        place(birds, bird_chirp() * rng.uniform(0.08, 0.2), at)
        at += rng.uniform(0.8, 3.5)
    x += reverb(birds, 0.25, 0.7)[: len(x)]
    return norm(loopify(x), 0.5)


def amb_frost():
    dur = 34.0
    t = t_axis(dur)
    x = wind(dur, 200, 2500, 0.4, 0.05) * 0.6
    # Howling: a resonant band whose centre slides up and down.
    howl = np.zeros_like(x)
    src = pink(dur)
    seg = SR // 4
    for i in range(0, len(src) - seg, seg):
        f = 500 + 380 * np.sin(2 * np.pi * 0.06 * i / SR) + 120 * np.sin(2 * np.pi * 0.23 * i / SR)
        howl[i:i + seg] = bp(src[i:i + seg + 400], f * 0.93, f * 1.07, 2)[:seg]
    x += howl * 1.4 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.045 * t) ** 2)
    x += bp(noise(dur), 4000, 9000) * 0.02   # blowing snow
    return norm(loopify(lp(x, 4000)), 0.55)


def amb_ember():
    dur = 34.0
    t = t_axis(dur)
    x = lp(brown(dur), 90) * 6 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.03 * t))
    crack = np.zeros_like(x)
    for _ in range(int(dur * 9)):
        n = int(rng.uniform(0.004, 0.02) * SR)
        c = hp(noise(n / SR), 1500) * np.exp(-np.arange(n) / (0.003 * SR))
        place(crack, c * rng.uniform(0.05, 0.3), rng.uniform(0, dur))
    x += crack
    # Lava bubbles: soft descending blips.
    for _ in range(int(dur * 0.8)):
        d = rng.uniform(0.08, 0.2)
        tt = t_axis(d)
        f = rng.uniform(120, 260) * (1 - 0.4 * tt / d)
        place(x, osc(f) * env(len(tt), 0.005, d * 0.8) * 0.2, rng.uniform(0, dur))
    return norm(loopify(x), 0.55)


def amb_glow():
    dur = 34.0
    t = t_axis(dur)
    x = np.zeros(len(t))
    for f in (220.0, 277.2, 329.6, 440.0):   # A minor-ish pad, slowly breathing
        detune = 1 + 0.003 * np.sin(2 * np.pi * rng.uniform(0.05, 0.1) * t)
        x += osc(f * detune) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.02, 0.05) * t + rng.random() * 6)) * 0.08
    shimmer = np.zeros_like(x)
    for _ in range(40):
        d = rng.uniform(1.0, 3.0)
        f = rng.choice([880, 1108.7, 1318.5, 1760, 2217.5])
        place(shimmer, osc(np.full(int(d * SR), f)) * env(int(d * SR), d * 0.4, d * 0.6) * 0.04, rng.uniform(0, dur))
    x += reverb(shimmer, 0.6, 1.3)[: len(x)]
    # Crickets: a 4.6 kHz tone gated in quick pulses.
    for k in range(3):
        gate = (np.sin(2 * np.pi * (28 + k * 3) * t) > 0.3) * (np.sin(2 * np.pi * (0.4 + k * 0.13) * t + k) > 0)
        x += osc(np.full(len(t), 4500 + k * 250)) * lp(gate.astype(float), 300) * 0.025
    return norm(loopify(x), 0.5)


def amb_village():
    dur = 34.0
    x = wind(dur, 150, 1000, 0.2) * 0.35
    birds = np.zeros_like(x)
    at = 1.0
    while at < dur - 2:
        place(birds, bird_chirp() * rng.uniform(0.04, 0.1), at)
        at += rng.uniform(2.0, 6.0)
    x += birds
    # Distant smithy: ringing anvil strikes in pairs.
    hits = np.zeros_like(x)
    at = 2.0
    while at < dur - 2:
        for k in range(rng.integers(2, 4)):
            n = int(0.9 * SR)
            tt = np.arange(n) / SR
            ring = sum(np.sin(2 * np.pi * f * tt) * a for f, a in ((1530, 1.0), (2470, 0.6), (3890, 0.3)))
            place(hits, ring * np.exp(-tt * 9) * 0.12, at + k * 0.55)
        at += rng.uniform(4.0, 8.0)
    x += reverb(lp(hits, 3000), 0.5, 1.2)[: len(x)]
    return norm(loopify(x), 0.45)

# ---------------------------------------------------------------- footsteps

def step(kind):
    n = int(0.22 * SR)
    tt = np.arange(n) / SR
    if kind == "grass":
        body = bp(noise(0.22), 300, 3500) * np.exp(-tt * 28)
        rustle = bp(noise(0.22), 2500, 8000) * np.exp(-((tt - 0.03) ** 2) / 0.0008) * 0.6
        thud = osc(np.full(n, rng.uniform(70, 95))) * np.exp(-tt * 40) * 0.7
        x = body + rustle + thud
    elif kind == "stone":
        click = hp(noise(0.22), 1800) * np.exp(-tt * 140)
        thud = osc(np.full(n, rng.uniform(90, 130))) * np.exp(-tt * 45)
        scuff = bp(noise(0.22), 800, 3000) * np.exp(-((tt - 0.05) ** 2) / 0.0006) * 0.25
        x = click * 0.8 + thud + scuff
    else:  # snow: compressed crunch, several tiny grains
        x = np.zeros(n)
        for _ in range(14):
            g = int(rng.uniform(0.003, 0.012) * SR)
            place(x, bp(noise(g / SR), 1200, 6000) * np.hanning(g), rng.uniform(0.0, 0.12))
        x += osc(np.full(n, 80)) * np.exp(-tt * 35) * 0.5
    return norm(x * env(n, 0.002, 0.08), rng.uniform(0.7, 0.9))


def jump():
    n = int(0.3 * SR)
    tt = np.arange(n) / SR
    return norm(bp(noise(0.3), 400, 3000) * np.sin(np.pi * tt / 0.3) ** 2, 0.5)


def land():
    n = int(0.35 * SR)
    tt = np.arange(n) / SR
    x = osc(np.full(n, 60)) * np.exp(-tt * 18) + bp(noise(0.35), 200, 2000) * np.exp(-tt * 25) * 0.6
    return norm(x, 0.85)

# ---------------------------------------------------------------- creatures

def voice(dur, f0_points, kind="saw", vib=(5.0, 0.02), form=(700, 1200, 2600), breath=0.2, rough=0.0):
    """Growl / call: oscillator along a pitch contour, vocal formants, breath noise."""
    t = t_axis(dur)
    f0 = np.interp(t, np.linspace(0, dur, len(f0_points)), f0_points)
    f0 = f0 * (1 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    if rough > 0:   # irregular pitch for snarls and roars
        f0 = f0 * (1 + rough * lp(noise(dur), 30) * 3)
    src = osc(f0, kind) + breath * noise(dur)
    return formants(src, form)


def deer_call():
    x = np.zeros(int(2.6 * SR))
    for k, at in enumerate((0.0, 0.9)):
        d = 0.75
        g = voice(d, [95, 120, 105, 80], form=(450, 900, 2200), breath=0.4, rough=0.03)
        place(x, g * env(len(g), 0.06, 0.25), at)
    return norm(reverb(x, 0.25, 1.4), 0.9)


def boar_grunt():
    x = np.zeros(int(1.6 * SR))
    for k in range(4):
        d = rng.uniform(0.12, 0.22)
        g = voice(d, [85, 70], kind="pulse", form=(350, 800, 1800), breath=0.8, rough=0.06)
        place(x, g * env(len(g), 0.01, 0.06), k * rng.uniform(0.25, 0.35))
    return norm(x, 0.85)


def wolf_howl():
    d = 3.6
    t = t_axis(d)
    g = voice(d, [380, 520, 610, 600, 560, 420], kind="sine", vib=(5.5, 0.012), form=(800, 1600, 3000), breath=0.05)
    g += 0.3 * osc(np.interp(t, np.linspace(0, d, 6), [380, 520, 610, 600, 560, 420]) * 2)
    return norm(reverb(g * env(len(g), 0.4, 0.9), 0.45, 1.6), 0.8)


def troll_grunt():
    d = 0.9
    g = voice(d, [75, 85, 65], form=(400, 750, 2000), breath=0.5, rough=0.08)
    return norm(np.tanh(g * 2.5) * env(len(g), 0.05, 0.3), 0.85)


def troll_roar():
    d = 2.0
    g = voice(d, [60, 95, 110, 90, 55], form=(500, 950, 2300), breath=0.9, rough=0.12)
    g = np.tanh(g * 4.0) + 0.4 * lp(brown(d), 120) * 8
    return norm(reverb(g * env(len(g), 0.12, 0.6), 0.3, 1.5), 0.95)


def spirit_whisper():
    d = 2.4
    t = t_axis(d)
    x = np.zeros(len(t))
    src = noise(d)
    for i in range(0, len(t) - SR // 10, SR // 10):   # breathy, shifting vowel
        f = 900 + 700 * np.sin(2 * np.pi * 0.7 * i / SR)
        x[i:i + SR // 10] = bp(src[i:i + SR // 10 + 300], f * 0.8, f * 1.25)[: SR // 10]
    x += osc(np.interp(t, [0, d], [1400, 1100])) * 0.08 * (1 + np.sin(2 * np.pi * 6 * t))
    return norm(reverb(x * env(len(t), 0.4, 0.8), 0.6, 1.8), 0.6)


def spirit_shriek():
    d = 1.6
    t = t_axis(d)
    f = np.interp(t, [0, 0.3, d], [600, 1700, 900])
    x = osc(f) + 0.5 * osc(f * 1.5) + 0.3 * osc(f * 2.01) + 0.4 * bp(noise(d), 2000, 6000)
    return norm(reverb(x * env(len(t), 0.05, 0.9), 0.55, 1.8), 0.75)


def golem_rumble():
    d = 2.2
    t = t_axis(d)
    x = lp(brown(d), 110) * 10 * env(len(t), 0.4, 0.8)
    for _ in range(30):   # grinding stone
        n = int(rng.uniform(0.01, 0.04) * SR)
        place(x, bp(noise(n / SR), 300, 1500) * np.hanning(n) * rng.uniform(0.1, 0.3), rng.uniform(0.2, d - 0.3))
    return norm(x, 0.85)


def golem_roar():
    d = 2.3
    g = voice(d, [45, 70, 75, 60, 40], form=(300, 600, 1500), breath=1.0, rough=0.15)
    g = np.tanh(g * 5.0) * 0.7 + lp(brown(d), 90) * 12
    for _ in range(25):
        n = int(rng.uniform(0.01, 0.05) * SR)
        place(g, bp(noise(n / SR), 200, 1200) * np.hanning(n) * 0.4, rng.uniform(0, d - 0.1))
    return norm(reverb(g * env(len(g), 0.15, 0.7), 0.3, 1.6), 0.95)


def salamander_hiss():
    d = 0.9
    t = t_axis(d)
    x = hp(noise(d), 2500) * env(len(t), 0.03, 0.5) * 0.7
    for _ in range(12):
        n = int(0.006 * SR)
        place(x, hp(noise(n / SR), 1500) * np.exp(-np.arange(n) / (0.002 * SR)), rng.uniform(0, d - 0.1))
    return norm(x, 0.8)


def beetle_chitter():
    d = 1.0
    x = np.zeros(int(d * SR))
    at = 0.0
    while at < d - 0.05:
        n = int(0.008 * SR)
        click = bp(noise(n / SR), 2500, 5500) * np.exp(-np.arange(n) / (0.0015 * SR))
        place(x, click * rng.uniform(0.5, 1.0), at)
        at += rng.uniform(0.018, 0.04)
    return norm(x * env(len(x), 0.05, 0.3), 0.75)


def beetle_hiss():
    d = 1.2
    x = hp(noise(d), 1800) * env(int(round(d * SR)), 0.05, 0.6) * 0.6
    place(x, beetle_chitter() * 0.6, 0.1)
    return norm(x, 0.85)


def main():
    save("ambience/meadow.ogg", amb_meadow())
    save("ambience/frost.ogg", amb_frost())
    save("ambience/ember.ogg", amb_ember())
    save("ambience/glow.ogg", amb_glow())
    save("ambience/village.ogg", amb_village())
    for kind in ("grass", "stone", "snow"):
        for i in range(4):
            save(f"steps/{kind}_{i}.ogg", step(kind), 2)
    save("steps/jump.ogg", jump(), 2)
    save("steps/land.ogg", land(), 2)
    for fn in (deer_call, boar_grunt, wolf_howl, troll_grunt, troll_roar, spirit_whisper, spirit_shriek,
               golem_rumble, golem_roar, salamander_hiss, beetle_chitter, beetle_hiss):
        save(f"creatures/{fn.__name__}.ogg", fn())


if __name__ == "__main__":
    main()
