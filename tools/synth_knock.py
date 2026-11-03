"""Synthesize wooden-fish (muyu) knock sounds with modal synthesis.

A hollow wooden temple block rings at a few inharmonic modes that decay
quickly, plus a short mallet-contact noise burst. Each knock also gets a
hall tail: the same knock heard in a large wooden hall, as the reverberation
alone. The app mixes in more of the tail the longer the quiet before a knock.

The sounds are original and released under CC0, like the project's other art
and sounds (the code itself is MIT).

Usage: python synth_knock.py <output_dir>
"""
import sys
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, fftconvolve, lfilter, resample_poly, sosfilt

SR = 44100
# A hall tail has little left above 8 kHz, so half the rate keeps it small.
TAIL_SR = SR // 2
TAIL_LENGTH_S = 3.0
# How loud the full tail is next to the knock itself: the knock carries this
# many times the tail's energy.
DIRECT_TO_HALL = 2.0


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


def hall_impulse(length_s: float = 2.8, seed: int = 108) -> np.ndarray:
    """Stereo impulse response of a large wooden hall, without the direct sound.

    A few early reflections off the floor, pillars and walls, then a dense
    tail that dies away faster in the highs than in the lows, as wood and air
    soak up the treble. Returns an array of shape (samples, 2).
    """
    rng = np.random.default_rng(seed)
    n = int(SR * length_s)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    early = [(13, 0.55), (19, 0.45), (27, 0.40), (34, 0.32), (46, 0.27), (58, 0.22), (71, 0.18)]
    # (low Hz, high Hz, gain, reverberation time RT60 in seconds)
    bands = [(40, 250, 1.00, 2.6), (250, 1000, 0.90, 2.3), (1000, 3500, 0.55, 1.6), (3500, 9000, 0.25, 0.8)]
    pre_delay = 0.02
    build_up = (t >= pre_delay) * (1 - np.exp(-np.maximum(t - pre_delay, 0) / 0.035))
    for ch in range(2):
        for delay_ms, gain in early:
            i = int((delay_ms + rng.uniform(-2.5, 2.5)) / 1000 * SR)
            ir[i, ch] += gain * rng.choice([-1.0, 1.0])
        noise = rng.normal(0, 1, n)
        late = np.zeros(n)
        for lo, hi, gain, rt60 in bands:
            sos = butter(4, [lo / (SR / 2), hi / (SR / 2)], btype="band", output="sos")
            band = sosfilt(sos, noise)
            late += gain * band / np.sqrt(np.mean(band**2)) * np.exp(-6.91 * t / rt60)
        ir[:, ch] += 0.12 * late * build_up
    return ir


def hall_tail(dry: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """The reverberation alone of `dry` in the hall, at TAIL_SR, faded out."""
    wet = np.stack([fftconvolve(dry, ir[:, ch]) for ch in range(2)], axis=1)
    wet = resample_poly(wet, 1, SR // TAIL_SR, axis=0)[: int(TAIL_SR * TAIL_LENGTH_S)]
    fade = int(0.4 * TAIL_SR)
    wet[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    return wet


def write_wav(path: Path, data: np.ndarray, rate: int = SR) -> None:
    pcm = (data * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1 if data.ndim == 1 else data.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


if __name__ == "__main__":
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    # Three slight variations so repeated knocks don't sound mechanical.
    knocks = [knock(base, seed=i) for i, base in enumerate([612.0, 598.0, 625.0])]
    ir = hall_impulse()
    tails = [hall_tail(k, ir) for k in knocks]
    # One gain for all three tails, so the hall sounds the same for each knock.
    # Energy is measured per channel and per second, at each file's own rate.
    dry_energy = np.mean([np.sum(k**2) / SR for k in knocks])
    tail_energy = np.mean([np.sum(w**2) / 2 / TAIL_SR for w in tails])
    gain = np.sqrt(dry_energy / DIRECT_TO_HALL / tail_energy)
    for i, (k, w) in enumerate(zip(knocks, tails)):
        write_wav(out_dir / f"knock{i + 1}.wav", k)
        write_wav(out_dir / f"knock{i + 1}-hall.wav", w * gain, TAIL_SR)
    print("wrote", sorted(p.name for p in out_dir.glob("knock*.wav")))
