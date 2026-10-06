// node mix.mjs <A|B|C>  -> soundtrack_<v>.wav
// Arranges Apple Loops (120 BPM, decoded to loops/*.wav) around the video's cuts, plus unpitched SFX.
import { readFileSync, writeFileSync } from 'node:fs';

const SR = 44100, DUR = 22.0, N = Math.round(SR * DUR);
const here = new URL('.', import.meta.url).pathname;
const L = new Float32Array(N), R = new Float32Array(N);
let seed = 11; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

const VARIANTS = {
  A: { beat: 'Minimal_Backbeat_01', intro: 'Moving_Pictures_Synth', bass: 'Moving_Pictures_Bass', main: 'Moving_Pictures_Rhythm_Guitar', lift: 'Moving_Pictures_Acoustic_Guitar' },
  B: { beat: 'Disco_Swagger_Beat_01', intro: 'Disco_Pop_Synth_Pad', bass: 'Disco_Pop_Bass', main: 'Disco_Pop_Rhythm_Guitar', lift: 'Disco_Pop_Synth_Stabs' },
  C: { beat: 'Doubledown_Beat_01', intro: 'Hyperlapse_Synth', bass: 'Hyperlapse_Bass', main: 'Hyperlapse_Guitar', lift: null },
};
const v = VARIANTS[process.argv[2] || 'A'];

function load(name) {
  const b = readFileSync(`${here}loops/${name}.wav`);
  let off = 12; while (b.toString('ascii', off, off + 4) !== 'data') off += 8 + b.readUInt32LE(off + 4);
  const f = new Float32Array(b.buffer.slice(b.byteOffset + off + 8, b.byteOffset + off + 8 + b.readUInt32LE(off + 4)));
  const n = f.length / 2, l = new Float32Array(n), r = new Float32Array(n);
  for (let i = 0; i < n; i++) { l[i] = f[2 * i]; r[i] = f[2 * i + 1]; }
  return { l, r, n };
}

// Place a looping stem. Loop position is phase-locked to `anchor` (a downbeat), so every
// stem stays in time no matter when it enters. gainAt(t) shapes it; lp(t) is an optional cutoff (Hz).
function stem(name, from, to, anchor, gain, gainAt = () => 1, lpAt = null) {
  const s = load(name); let y1l = 0, y1r = 0, y2l = 0, y2r = 0;
  for (let j = Math.round(from * SR); j < Math.min(N, Math.round(to * SR)); j++) {
    const t = j / SR, k = (((j - Math.round(anchor * SR)) % s.n) + s.n) % s.n;
    let a = s.l[k], b = s.r[k];
    if (lpAt) {
      const c = 1 - Math.exp(-2 * Math.PI * lpAt(t) / SR);
      y1l += c * (a - y1l); y2l += c * (y1l - y2l); y1r += c * (b - y1r); y2r += c * (y1r - y2r); a = y2l; b = y2r;
    }
    const g = gain * gainAt(t); L[j] += a * g; R[j] += b * g;
  }
}
const ramp = (t, a, b) => Math.min(1, Math.max(0, (t - a) / (b - a)));
const add = (buf, t0, gain, pan = 0) => {
  const s0 = Math.round(t0 * SR), gl = Math.cos((pan + 1) * Math.PI / 4) * gain * 1.41, gr = Math.sin((pan + 1) * Math.PI / 4) * gain * 1.41;
  for (let i = 0; i < buf.length; i++) { const j = s0 + i; if (j >= 0 && j < N) { L[j] += buf[i] * gl; R[j] += buf[i] * gr; } }
};

// --- arrangement. Downbeats every 2s from 0.5; the drop is 2.5, the outro restarts loops at 19.0.
const D = 2.5, END_FADE = (t) => 1 - ramp(t, 21.0, 22.0);
// Intro under the hook: the phrase's last bars, filtered open into the drop
stem(v.intro, 0, 19.0, D, 0.75, (t) => (t < D ? 0.35 + 0.65 * ramp(t, 0, D) : 1),
  (t) => (t < D ? 350 * Math.pow(9000 / 350, Math.pow(ramp(t, 0, D), 2)) : t > 18.0 ? 9000 * Math.pow(500 / 9000, ramp(t, 18.0, 18.95)) : 9000));
stem(v.bass, D, 18.5, D, 0.85);
stem(v.beat, D, 18.5, D, 0.9);
stem(v.main, 5.5, 18.5, D, 0.6, (t) => ramp(t, 5.5, 5.6));
if (v.lift) stem(v.lift, 8.5, 18.5, D, 0.42);
// Outro: everyone back in on the downbeat at 19.0, drums for one bar, then a fade
for (const [name, g] of [[v.intro, 0.75], [v.bass, 0.85], [v.main, 0.6]]) stem(name, 19.0, 22.0, 19.0, g, END_FADE);
if (v.lift) stem(v.lift, 19.0, 22.0, 19.0, 0.42, END_FADE);
stem(v.beat, 19.0, 21.0, 19.0, 0.9, (t) => 1 - ramp(t, 20.9, 21.0));

// --- SFX: unpitched so they can't clash with the loops' key
function thump() { const n = Math.round(0.4 * SR), o = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR; ph += 2 * Math.PI * (45 + 90 * Math.exp(-t * 30)) / SR; o[i] = Math.tanh(1.5 * Math.sin(ph) * Math.exp(-t * 8)); } return o; }
function click(fc = 3000, dec = 400) { const n = Math.round(0.04 * SR), o = new Float32Array(n); let y = 0; const c = 1 - Math.exp(-2 * Math.PI * fc / SR);
  for (let i = 0; i < n; i++) { y += c * (rnd() - y); o[i] = y * Math.exp(-i / SR * dec); } return o; }
function whoosh(dur, f0 = 250, f1 = 1800, peak = 0.55) { const n = Math.round(dur * SR), o = new Float32Array(n); let y1 = 0, y2 = 0;
  for (let i = 0; i < n; i++) { const p = i / n, fc = f0 * Math.pow(f1 / f0, p < peak ? p / peak : 1 - (p - peak) / (1 - peak) * 0.7), c = 1 - Math.exp(-2 * Math.PI * fc / SR);
    y1 += c * (rnd() - y1); y2 += c * (y1 - y2); o[i] = y2 * (p < peak ? (p / peak) ** 2 : (1 - (p - peak) / (1 - peak)) ** 1.6); } return o; }

[0, 0.5, 1.0].forEach((t) => add(thump(), t, 0.5));
for (let i = 0; i < 7; i++) add(click(4000, 600), 2.65 + i / 14, 0.05);
for (let i = 0; i < 7; i++) add(click(4000, 600), 19.15 + i / 18, 0.045);
[7.75, 10.6, 11.6].forEach((t) => { add(click(2200, 250), t, 0.22, 0.15); add(thump(), t, 0.08); });
[[5.45, 0.6], [8.2, 0.45], [9.25, 0.45], [11.72, 0.4], [12.95, 0.55], [16.4, 0.45]].forEach(([t, d]) => add(whoosh(d), t, 0.16));
add(whoosh(0.8, 300, 2600, 0.5), 17.1, 0.16);
add(whoosh(0.6, 200, 3000, 0.92), 18.4, 0.22); // lift into the outro re-entry

// --- write 32-bit float WAV (normalized by ffmpeg loudnorm afterwards)
let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
const g = 0.9 / peak, pcm = Buffer.alloc(N * 8);
for (let i = 0; i < N; i++) { pcm.writeFloatLE(L[i] * g, i * 8); pcm.writeFloatLE(R[i] * g, i * 8 + 4); }
const h = Buffer.alloc(44);
h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12);
h.writeUInt32LE(16, 16); h.writeUInt16LE(3, 20); h.writeUInt16LE(2, 22); h.writeUInt32LE(SR, 24);
h.writeUInt32LE(SR * 8, 28); h.writeUInt16LE(8, 32); h.writeUInt16LE(32, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
writeFileSync(`${here}soundtrack_${process.argv[2] || 'A'}.wav`, Buffer.concat([h, pcm]));
console.log(process.argv[2], 'peak', peak.toFixed(2));
