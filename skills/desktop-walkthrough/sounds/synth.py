#!/usr/bin/env python3
"""Render the HUD's sound effects as 16-bit mono WAV files (44.1 kHz).

Why it exists: the HUD answers reading with sound (a block marked as read, a note understood, a
page cleared). The sounds are synthesized here from a few lines each, so the skill carries their
source and no audio files; `dw` runs this before it starts the HUD, when the files are missing or
older than this script. The HUD plays them from <state>/sounds (see hud/Sound.swift).

Usage: python3 -I synth.py <output folder>

The set is one family (a wooden bar, a plucked string, a small bell) at four levels, quiet to loud:
  tick                 a feedback button, the focus moving without a mark
  mark                 a block marked as read: two rising notes, the same for every block
  unmark               a mark taken back
  note, complete       a note understood; every block of a page read
  next                 the page cleared: the only fanfare
A rising pitch reads as "good", a level one as neutral; the frequent sounds are the short, quiet ones.
"""
import json
import math
import os
import random
import struct
import sys
import wave

SR = 44100
TAU = math.tau
NOTES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """Frequency of a note name such as 'C5' or 'F#4' (A4 = 440 Hz)."""
    letter, rest = name[0], name[1:]
    semitone = NOTES[letter]
    while rest and rest[0] in "#b":
        semitone += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 440.0 * 2 ** ((semitone - 9 + (int(rest) - 4) * 12) / 12)


def mix(dst, src, at=0.0, gain=1.0):
    """Add `src` into `dst` starting `at` seconds, growing `dst` as needed."""
    start = int(at * SR)
    need = start + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, sample in enumerate(src):
        dst[start + i] += sample * gain
    return dst


def partials(freq, dur, spec, tau, attack=0.002):
    """Sum of decaying sine partials: spec = [(ratio, amplitude, how much faster it dies)]."""
    n = int(dur * SR)
    out = [0.0] * n
    a = max(1, int(attack * SR))
    for ratio, amp, speed in spec:
        f = freq * ratio
        if f > SR * 0.45:
            continue
        w = TAU * f / SR
        k = math.exp(-1.0 / (tau / speed * SR))
        level = amp
        for i in range(n):
            out[i] += math.sin(w * i) * level * (i / a if i < a else 1.0)
            level *= k
    return out


def noise(dur, tau, lp, attack=0.0005):
    """A short burst of low-passed noise: the knock on the front of a struck bar."""
    n = int(dur * SR)
    out = []
    low = 0.0
    a = 1 - math.exp(-TAU * lp / SR)
    ramp = max(1, int(attack * SR))
    for i in range(n):
        low += a * (random.uniform(-1, 1) - low)
        out.append(low * math.exp(-(i / SR) / tau) * (i / ramp if i < ramp else 1.0))
    return out


def marimba(freq, dur=0.3, tau=0.11):
    """Wooden bar: a strong fundamental with a knock on top."""
    out = partials(freq, dur, [(1, 1.0, 1), (3.93, 0.3, 3.5), (9.2, 0.08, 7)], tau, attack=0.001)
    return mix(out, noise(0.006, 0.002, 5000), 0, 0.25)


def bell(freq, dur=0.6, tau=0.28):
    """Small glockenspiel: inharmonic partials, the high ones dying first."""
    return partials(freq, dur, [(1, 1.0, 1), (2.756, 0.45, 1.7), (5.404, 0.22, 2.8), (8.933, 0.1, 4.5)], tau)


def pluck(freq, dur=0.8, damp=0.996, bright=0.5):
    """Karplus-Strong string: a harp pluck."""
    period = max(2, int(round(SR / freq)))
    line = [random.uniform(-1, 1) for _ in range(period)]
    for _ in range(2):
        line = [(line[i] * bright + line[i - 1] * (1 - bright)) for i in range(period)]
    out = []
    idx = 0
    for _ in range(int(dur * SR)):
        nxt = (idx + 1) % period
        value = line[idx]
        out.append(value)
        line[idx] = damp * 0.5 * (value + line[nxt])
        idx = nxt
    return out


def reverb(x, wet=0.22, feedback=0.78, tail=0.6):
    """A small Schroeder reverb (four combs into two all-passes): a little room around the louder sounds."""
    n = len(x) + int(tail * SR)
    dry = x + [0.0] * (n - len(x))
    acc = [0.0] * n
    for delay in (1557, 1617, 1491, 1422):
        buf = [0.0] * delay
        pos = 0
        for i in range(n):
            y = buf[pos]
            buf[pos] = dry[i] + y * feedback
            acc[i] += y
            pos = (pos + 1) % delay
    for delay in (225, 556):
        buf = [0.0] * delay
        pos = 0
        for i in range(n):
            delayed = buf[pos]
            v = acc[i] + delayed * 0.7
            buf[pos] = v
            acc[i] = delayed - v * 0.7
            pos = (pos + 1) % delay
    return [dry[i] + acc[i] * wet * 0.25 for i in range(n)]


def loudest_rms(x, window=0.05, hop=0.01):
    """RMS of the loudest 50 ms. A shorter sound is averaged over the whole window, as the ear does."""
    w = max(1, int(window * SR))
    h = max(1, int(hop * SR))
    acc = [0.0]
    for sample in x:
        acc.append(acc[-1] + sample * sample)
    if len(x) <= w:
        return math.sqrt(acc[-1] / w)
    return math.sqrt(max((acc[start + w] - acc[start]) / w for start in range(0, len(x) - w + 1, h)))


def finish(x, level_db, fade=0.015):
    """Bring the loudest moment to `level_db` (RMS), keep the peak under -1.5 dBFS, fade the end."""
    peak = max(1e-9, max(abs(sample) for sample in x))
    gain = min(10 ** (level_db / 20) / max(1e-9, loudest_rms(x)), 10 ** (-1.5 / 20) / peak)
    out = [sample * gain for sample in x]
    r = min(len(out), int(fade * SR))
    for i in range(r):
        out[-1 - i] *= i / r
    return out


def seq(voice, notes, step, **kw):
    """Notes one after another: [(name, duration)], one every `step` seconds, through `voice`."""
    out = []
    for i, (name, dur) in enumerate(notes):
        mix(out, voice(hz(name), dur, **kw), i * step)
    return out


def sounds():
    """Every sound as name -> (samples, level in dB RMS of its loudest moment)."""
    random.seed(7)

    out = {"tick": (marimba(hz("G5"), 0.12, tau=0.045), -31)}
    # The same two notes for every block: the mark does not climb as a page fills up
    mark = marimba(hz("D5"), 0.16, tau=0.07)
    out["mark"] = (mix(mark, marimba(hz("G5"), 0.32, tau=0.11), 0.075), -23)
    out["unmark"] = (marimba(hz("A4"), 0.16, tau=0.06), -33)

    note = marimba(hz("B4"), 0.3)
    mix(note, marimba(hz("D5"), 0.3), 0.0, 0.8)
    mix(note, marimba(hz("G5"), 0.4, tau=0.14), 0.1)
    mix(note, bell(hz("G6"), 0.7, tau=0.3), 0.1, 0.22)
    out["note"] = (reverb(note, wet=0.14), -20)

    done = seq(marimba, [("G4", 0.25), ("B4", 0.25), ("D5", 0.25), ("G5", 0.45)], 0.075, tau=0.12)
    mix(done, bell(hz("D6"), 0.6, tau=0.25), 0.225, 0.25)
    out["complete"] = (reverb(done, wet=0.16), -20)

    fan = seq(pluck, [("C4", 0.9), ("E4", 0.9), ("G4", 0.9), ("C5", 0.9), ("E5", 0.9), ("G5", 0.9)], 0.075, damp=0.995)
    for name in ("C5", "E5", "G5"):
        mix(fan, marimba(hz(name), 0.6, tau=0.2), 0.47, 0.9)
    mix(fan, pluck(hz("C3"), 1.2, damp=0.997), 0.47, 0.9)
    mix(fan, bell(hz("C6"), 1.0, tau=0.4), 0.47, 0.35)
    mix(fan, bell(hz("G6"), 1.0, tau=0.45), 0.62, 0.28)
    mix(fan, bell(hz("C7"), 1.0, tau=0.45), 0.77, 0.2)
    out["next"] = (reverb(fan, wet=0.24, tail=0.8), -15)
    return out


def write(folder, name, samples, level_db):
    """Write one sound as <folder>/<name>.wav; returns its length in seconds."""
    samples = finish(samples, level_db)
    with wave.open(os.path.join(folder, f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SR)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in samples))
    return round(len(samples) / SR, 3)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: synth.py <output folder>")
    target = sys.argv[1]
    os.makedirs(target, exist_ok=True)
    lengths = {name: write(target, name, samples, level) for name, (samples, level) in sounds().items()}
    # Written last: its presence says the folder is complete
    with open(os.path.join(target, "sounds.json"), "w") as index:
        json.dump(lengths, index, indent=2)
    print(", ".join(f"{name} {seconds}s" for name, seconds in lengths.items()))
