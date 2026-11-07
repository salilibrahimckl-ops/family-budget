# Applied in CI after `npx cap add android`: icons, splash, permissions, deep link, version.
import os, re, shutil, sys, glob
run = int(sys.argv[1]) if len(sys.argv) > 1 else 1
res = 'android/app/src/main/res'
for d in glob.glob('assets/android/*'):
    dst = os.path.join(res, os.path.basename(d)); os.makedirs(dst, exist_ok=True)
    for f in os.listdir(d): shutil.copy(os.path.join(d, f), os.path.join(dst, f))
for d in glob.glob(res + '/drawable*'):
    if os.path.exists(d + '/splash.png'): shutil.copy('assets/android/drawable/splash.png', d + '/splash.png')
bg = res + '/values/ic_launcher_background.xml'
if os.path.exists(bg): open(bg, 'w').write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#0A0C0F</color>\n</resources>\n')
m = 'android/app/src/main/AndroidManifest.xml'; s = open(m).read()
perms = ['android.permission.CAMERA', 'android.permission.POST_NOTIFICATIONS', 'android.permission.VIBRATE']
for p in perms:
    if p not in s: s = s.replace('</manifest>', f'    <uses-permission android:name="{p}" />\n</manifest>')
if 'com.fitverse.app' not in s.split('<activity')[1] if '<activity' in s else True:
    pass
link = '''            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="com.fitverse.app" android:host="auth-callback" />
            </intent-filter>
'''
if 'auth-callback' not in s: s = s.replace('        </activity>', link + '        </activity>', 1)
open(m, 'w').write(s)
g = 'android/app/build.gradle'; t = open(g).read()
t = re.sub(r'versionCode \d+', f'versionCode {100 + run}', t); t = re.sub(r'versionName "[^"]*"', f'versionName "1.0.{run}"', t)
open(g, 'w').write(t)
print('patched android, versionCode', 100 + run)
