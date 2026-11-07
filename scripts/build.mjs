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
<meta name="apple-mobile-web-app-title" content="FITVERSE" />
<meta name="description" content="FITVERSE — premium fitness, nutrition and community app." />
<link rel="icon" href="data:image/svg+xml,${encodeURIComponent(icon)}" />
<link rel="apple-touch-icon" href="data:image/svg+xml,${encodeURIComponent(icon)}" />
<title>FITVERSE</title>
<style>${css}</style>
</head>
<body>
<div id="root"></div>
<script>${js.replace(/<\/script/g, '<\\/script')}</script>
</body>
</html>`;
fs.writeFileSync(path.join(out, 'index.html'), html);
console.log('www/index.html', (html.length / 1024).toFixed(0) + ' KB');
