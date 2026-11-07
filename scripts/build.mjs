// Builds the web bundle into www/ (used by Capacitor for the Android APK and as the iPhone web app).
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const out = path.join(root, 'www');
fs.mkdirSync(out, { recursive: true });
const nodePaths = [path.join(root, 'node_modules'), '/opt/npm-tools/node_modules'].filter((p) => fs.existsSync(p));
const cloudCfg = (() => { try { const c = JSON.parse(fs.readFileSync(path.join(root, 'config/cloud.json'), 'utf8')); return { url: c.supabaseUrl || '', key: c.supabaseAnon || '' }; } catch { return { url: '', key: '' }; } })();
const r = await build({
  entryPoints: [path.join(root, 'src/App.tsx')], bundle: true, minify: true, format: 'iife', target: ['chrome90', 'safari15'],
  jsx: 'automatic', define: { 'process.env.NODE_ENV': '"production"', __FV_CLOUD_URL__: JSON.stringify(cloudCfg.url), __FV_CLOUD_KEY__: JSON.stringify(cloudCfg.key) }, write: false, nodePaths, legalComments: 'none',
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
const NATIVE = (() => { try { return JSON.parse(fs.readFileSync(path.join(root, 'config/native.json'), 'utf8')).nativeBuild || 0; } catch { return 0; } })();
fs.writeFileSync(path.join(ota, 'version.json'), JSON.stringify({ build: BUILD, notes, date: new Date().toISOString(), minBuiltIn: MIN_BUILT_IN, nativeBuild: NATIVE }));
fs.writeFileSync(path.join(ota, 'bundle.json'), JSON.stringify({ build: BUILD, js, css }));
// iPhone / browser web app (served from GitHub Pages at /family-budget/fitness/). A tiny loader that always runs the
// newest published bundle, keeps a copy for offline use, and can be added to the iPhone home screen.
const touch = fs.readFileSync(path.join(root, 'assets/apple-touch-icon.png')).toString('base64');
const manifest = { name: 'Bro’s Fitness', short_name: 'Bro’s Fitness', start_url: '.', display: 'standalone', background_color: '#0A0C0F', theme_color: '#0A0C0F', icons: [{ src: 'data:image/png;base64,' + touch, sizes: '180x180', type: 'image/png' }] };
const pages = `<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, maximum-scale=1" />
<meta name="theme-color" content="#0A0C0F" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="Bro’s Fitness" />
<link rel="apple-touch-icon" href="data:image/png;base64,${touch}" />
<link rel="icon" href="data:image/png;base64,${touch}" />
<link rel="manifest" href="data:application/manifest+json,${encodeURIComponent(JSON.stringify(manifest))}" />
<title>Bro’s Fitness</title>
<style>html,body{margin:0;background:#0A0C0F;color:#fff;font-family:-apple-system,system-ui,sans-serif}#fv-load{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px}#fv-load i{width:42px;height:42px;border-radius:50%;border:4px solid #222;border-top-color:#C6FF3D;animation:s 1s linear infinite}@keyframes s{to{transform:rotate(360deg)}}#fv-load small{color:#8a9099}</style>
</head>
<body>
<div id="fv-load"><i></i><small>Loading Bro’s Fitness…</small></div>
<div id="root"></div>
<script>
(function(){
  var R='https://raw.githubusercontent.com/salilibrahimckl-ops/family-budget/fitverse-builds/';
  var K='fvw.bundle', ran=false;
  function run(txt){ if(ran) return; var b; try{ b=JSON.parse(txt) }catch(e){ return false }
    ran=true; window.__FV_BUILD=b.build; window.__FV_BUILT_IN=b.build; window.__FV_WEB=1;
    var st=document.createElement('style'); st.id='fv-style'; st.textContent=b.css; document.head.appendChild(st);
    var l=document.getElementById('fv-load'); if(l) l.remove();
    var s=document.createElement('script'); s.textContent=b.js; document.body.appendChild(s); return true }
  function save(t){ try{ localStorage.setItem(K,t) }catch(e){ try{ localStorage.removeItem(K) }catch(_){} } }
  var cached=null; try{ cached=localStorage.getItem(K) }catch(e){}
  if(cached) run(cached);
  fetch(R+'bundle.json?t='+Date.now(),{cache:'no-store'}).then(function(r){ if(!r.ok) throw 0; return r.text() }).then(function(t){
    save(t); if(!ran) run(t);
  }).catch(function(){ if(!ran){ var l=document.getElementById('fv-load'); if(l) l.innerHTML='<small>No internet — open once online to install the app.</small>' } });
})();
</script>
</body>
</html>`;
fs.writeFileSync(path.join(ota, 'fitverse-pages.html'), pages);
// Privacy page (shown by Android's Health Connect when the user taps "privacy policy")
fs.writeFileSync(path.join(out, 'privacy.html'), `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bro’s Fitness — Privacy</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:0 auto;padding:20px;line-height:1.55;color:#222}h1{font-size:22px}</style></head><body>
<h1>Bro’s Fitness — health data & privacy</h1>
<p>If you connect Health Connect, Bro’s Fitness <b>reads</b> your steps, active and total calories burnt, distance and exercise sessions (for example from Samsung Health or your smartwatch) so it can show your daily burn and log your sports automatically.</p>
<ul><li>This data is stored <b>on your phone</b> only.</li><li>It is never sold or shared with advertisers. Nothing is written back to Health Connect.</li>
<li>If you join the community leaderboard, only weekly totals (calories, active minutes, sessions, streak) are shared with signed-in members. You can turn this off in Settings → Privacy.</li>
<li>You can disconnect at any time in Settings → Smartwatch, or in the Health Connect app.</li></ul>
<p>Questions: contact the app owner.</p></body></html>`);
