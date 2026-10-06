// node render.mjs stills 0.6 3.9 ...   -> stills/t_<t>.png
// node render.mjs video                 -> frames piped to ffmpeg -> video_silent.mp4
import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const here = path.dirname(new URL(import.meta.url).pathname);
const FPS = 30, DUR = 22.0;
const [mode, ...rest] = process.argv.slice(2);

const browser = await chromium.launch({ channel: 'chrome', args: ['--force-color-profile=srgb', '--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(here, 'index.html'));
await page.evaluate(() => window.ready);

const shot = async (t) => {
  await page.evaluate((t) => window.renderAt(t), t);
  await page.evaluate(() => new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))));
  return page.screenshot({ type: 'png' });
};

if (mode === 'stills') {
  mkdirSync(path.join(here, 'stills'), { recursive: true });
  const { writeFileSync } = await import('node:fs');
  for (const s of rest) writeFileSync(path.join(here, 'stills', `t_${s}.png`), await shot(parseFloat(s)));
} else {
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', path.join(here, 'video_silent.mp4')], { stdio: ['pipe', 'inherit', 'inherit'] });
  const N = Math.round(FPS * DUR);
  for (let i = 0; i < N; i++) {
    const buf = await shot(i / FPS);
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (i % 60 === 0) console.log(`frame ${i}/${N}`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
}
await browser.close();
