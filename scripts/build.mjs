// Builds the web bundle into www/ (used by Capacitor for the Android APK and as the iPhone web app).
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const out = path.join(root, 'www');
fs.mkdirSync(out, { recursive: true });
const nodePaths = [path.join(root, 'node_modules'), '/opt/npm-tools/node_modules'].filter((p) => fs.existsSync(p));
const r = await build({
  entryPoints: [path.join(root, 'src/App.tsx')], bundle: true, minify: true, format: 'iife', target: ['chrome90', 'safari15'],
  jsx: 'automatic', define: { 'process.env.NODE_ENV': '"production"' }, write: false, nodePaths, legalComments: 'none',
});
const js = r.outputFiles[0].text;
const BUILD = Number(process.env.FV_BUILD || 0);
const MIN_BUILT_IN = Number(process.env.FV_MIN_BUILT_IN || 5); // bundles need an APK that has the updater (build 5+)
// Boot: in the Android app, run a newer downloaded bundle (if any) instead of the built-in one, with crash fallback.
const boot = `(function(){var B=${BUILD};window.__FV_BUILT_IN=B;window.__FV_BUILD=B;try{if(!(window.Capacitor&&window.Capacitor.isNativePlatform&&window.Capacitor.isNativePlatform()))return;var v=+localStorage.getItem('fv.ota.v')||0,bad=+localStorage.getItem('fv.ota.bad')||0,bt=+localStorage.getItem('fv.ota.booting')||0;if(v<=B||v===bad)return;if(bt===v){localStorage.setItem('fv.ota.bad',v);return}var j=localStorage.getItem('fv.ota.js'),c=localStorage.getItem('fv.ota.css');if(!j||!c)return;localStorage.setItem('fv.ota.booting',v);window.__FV_OTA=1;window.__FV_BUILD=v;var o=document.getElementById('fv-style');if(o)o.remove();var st=document.createElement('style');st.textContent=c;document.head.appendChild(st);document.addEventListener('DOMContentLoaded',function(){var s=document.createElement('script');s.textContent=j;document.body.appendChild(s)})}catch(e){}})();`;
const wrapped = 'if(!window.__FV_OTA){' + js + '}';
const css = fs.readFileSync(path.join(root, 'src/styles.css'), 'utf8');
const icon = fs.readFileSync(path.join(root, 'assets/icon.svg'), 'utf8');
const html = `<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, maximum-scale=1" />
<meta name="theme-color" content="#0A0C0F" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="Bro’s Fitness" />
<meta name="description" content="Bro’s Fitness — premium fitness, nutrition and community app." />
<link rel="icon" href="data:image/svg+xml,${encodeURIComponent(icon)}" />
<link rel="apple-touch-icon" href="data:image/svg+xml,${encodeURIComponent(icon)}" />
<title>Bro’s Fitness</title>
<style id="fv-style">${css}</style>
<script>${boot}</script>
</head>
<body>
<div id="root"></div>
<script>${wrapped.replace(/<\/script/g, '<\\/script')}</script>
</body>
</html>`;
fs.writeFileSync(path.join(out, 'index.html'), html);
console.log('www/index.html', (html.length / 1024).toFixed(0) + ' KB', 'build', BUILD);
// Over-the-air update files (published to the build branch by CI)
const ota = path.join(root, 'dist-ota'); fs.mkdirSync(ota, { recursive: true });
const notesFile = path.join(root, 'docs/WHATSNEW.txt');
const notes = fs.existsSync(notesFile) ? fs.readFileSync(notesFile, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean).slice(0, 6) : [];
fs.writeFileSync(path.join(ota, 'version.json'), JSON.stringify({ build: BUILD, notes, date: new Date().toISOString(), minBuiltIn: MIN_BUILT_IN }));
fs.writeFileSync(path.join(ota, 'bundle.json'), JSON.stringify({ build: BUILD, js, css }));
