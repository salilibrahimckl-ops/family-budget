// Generates Android launcher icons + splash from assets/icon.svg (run locally; outputs committed in assets/android).
import sharp from 'sharp'; import fs from 'node:fs';
const svg = fs.readFileSync('assets/icon.svg');
const fg = Buffer.from(fs.readFileSync('assets/icon.svg', 'utf8').replace(/<rect[^>]*\/>/, '').replace('viewBox="0 0 512 512"', 'viewBox="-128 -128 768 768"'));
const d = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
for (const [k, s] of Object.entries(d)) {
  const dir = `assets/android/mipmap-${k}`; fs.mkdirSync(dir, { recursive: true });
  await sharp(svg).resize(s, s).png().toFile(`${dir}/ic_launcher.png`);
  const r = Buffer.from(`<svg width="${s}" height="${s}"><circle cx="${s/2}" cy="${s/2}" r="${s/2}"/></svg>`);
  await sharp(svg).resize(s, s).composite([{ input: r, blend: 'dest-in' }]).png().toFile(`${dir}/ic_launcher_round.png`);
  await sharp(fg).resize(Math.round(s * 2.25), Math.round(s * 2.25)).png().toFile(`${dir}/ic_launcher_foreground.png`);
}
const splashSvg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280"><rect width="1280" height="1280" fill="#0A0C0F"/><g transform="translate(440 400) scale(0.78)">${fs.readFileSync('assets/icon.svg','utf8').replace(/^<svg[^>]*>/,'').replace('</svg>','')}</g><text x="640" y="900" text-anchor="middle" font-family="Arial, sans-serif" font-weight="900" font-size="76" letter-spacing="6" fill="#fff">BRO’S <tspan fill="#C6FF3D">FITNESS</tspan></text></svg>`);
fs.mkdirSync('assets/android/drawable', { recursive: true });
await sharp(splashSvg).png().toFile('assets/android/drawable/splash.png');
await sharp(svg).resize(1024, 1024).png().toFile('assets/icon-1024.png');
await sharp(splashSvg).resize(640,640).png().toFile('assets/splash-preview.png');
console.log('icons ok');
