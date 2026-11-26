#!/usr/bin/env python3
"""Synthesizes the menu sounds (no recordings). Author: Claude (Openworld).

sfx/ (game/assets/audio/sfx):
  ui_click   soft wooden tap with a faint metal ring (buttons, tabs)
  ui_open    low cloth swoosh and a quiet chime (menus, journal opening)
  page_turn  a parchment page turning (journal sections)

Run from the repo root: python3 tools/audio/synth_ui.py  (needs numpy, scipy, ffmpeg)
"""
import numpy as np

from synth_expansion import SR, bp, lp, noise, save, t

rng = np.random.default_rng(4242)


def ui_click():
    d = 0.12
    tt = t(d)
    tap = bp(noise(d), 900, 3200) * np.exp(-tt * 90)
    ring = np.sin(2 * np.pi * 2350 * tt) * np.exp(-tt * 45) * 0.18
    return tap + ring


def ui_open():
    d = 0.7
    tt = t(d)
    env = np.sin(np.pi * np.clip(tt / 0.45, 0, 1)) ** 2
    swoosh = lp(noise(d), 1400) * env * 0.6
    chime = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * k) * a
                for f, k, a in ((880, 5.5, 0.22), (1320, 7.0, 0.12), (1760, 9.0, 0.06)))
    chime[: int(0.12 * SR)] = 0.0   # the chime lands after the swoosh starts
    return swoosh + chime


def page_turn():
    d = 0.55
    tt = t(d)
    rustle = bp(noise(d), 1800, 7000) * (0.5 + 0.5 * np.sin(2 * np.pi * 21 * tt + rng.uniform(0, 6)))
    env = np.clip(tt / 0.05, 0, 1) * np.exp(-((tt - 0.22) / 0.16) ** 2)
    flap = lp(noise(d), 500) * np.exp(-((tt - 0.38) / 0.03) ** 2) * 1.4
    return rustle * env + flap


def main():
    save("sfx", "ui_click", ui_click(), peak=0.5)
    save("sfx", "ui_open", ui_open(), peak=0.55)
    save("sfx", "page_turn", page_turn(), peak=0.6)


if __name__ == "__main__":
    main()
