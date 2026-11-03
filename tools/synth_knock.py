"""Synthesize wooden-fish (muyu) knock sounds with modal synthesis.

A hollow wooden temple block rings at a few inharmonic modes that decay
quickly, plus a short mallet-contact noise burst. Output is original,
released under CC0 along with the rest of this project.

Usage: python synth_knock.py <output_dir>
"""
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100


def knock(base_hz: float, length_s: float = 0.9, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * length_s)) / SR
    # (ratio to base, amplitude, decay time constant in seconds)
    modes = [
        (1.00, 1.00, 0.110),
        (1.52, 0.45, 0.070),
        (2.31, 0.30, 0.045),
        (3.07, 0.18, 0.030),
        (4.63, 0.10, 0.018),
    ]
    out = np.zeros_like(t)
    for ratio, amp, tau in modes:
        f = base_hz * ratio * (1 + rng.normal(0, 0.004))
        phase = rng.uniform(0, 2 * np.pi)
        out += amp * np.exp(-t / tau) * np.sin(2 * np.pi * f * t + phase)
    # Cavity "body" resonance: low hollow tone with slightly longer tail.
    out += 0.35 * np.exp(-t / 0.16) * np.sin(2 * np.pi * base_hz * 0.5 * t)
    # Mallet contact: band-passed noise burst of a few milliseconds.
    noise = rng.normal(0, 1, len(t)) * np.exp(-t / 0.004)
    b, a = butter(2, [1500 / (SR / 2), 7000 / (SR / 2)], btype="band")
    out += 0.6 * lfilter(b, a, noise)
    # Soft attack (1 ms) to avoid a digital click.
    attack = np.minimum(1.0, t / 0.001)
    out *= attack
    # Fade the last 50 ms.
    fade = np.ones_like(t)
    n = int(0.05 * SR)
    fade[-n:] = np.linspace(1, 0, n)
    out *= fade
    return out / np.max(np.abs(out)) * 0.85


def write_wav(path: Path, data: np.ndarray) -> None:
    pcm = (data * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    # Three slight variations so repeated knocks don't sound mechanical.
    for i, base in enumerate([612.0, 598.0, 625.0]):
        write_wav(out_dir / f"knock{i + 1}.wav", knock(base, seed=i))
    print("wrote", sorted(p.name for p in out_dir.glob("knock*.wav")))
