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
# Health Connect (Samsung Health, Galaxy Watch, Fitbit, Garmin & other watches that sync to it)
hc_perms = ['READ_STEPS', 'READ_ACTIVE_CALORIES_BURNED', 'READ_TOTAL_CALORIES_BURNED', 'READ_DISTANCE', 'READ_EXERCISE']
for hp in hc_perms:
    full = 'android.permission.health.' + hp
    if full not in s: s = s.replace('</manifest>', f'    <uses-permission android:name="{full}" />\n</manifest>')
if 'com.google.android.apps.healthdata' not in s:
    s = s.replace('</manifest>', '    <queries>\n        <package android:name="com.google.android.apps.healthdata" />\n    </queries>\n</manifest>')
rationale = '''        <activity android:name="com.fit_up.health.capacitor.PermissionsRationaleActivity" android:exported="true">
            <intent-filter><action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" /></intent-filter>
        </activity>
        <activity-alias android:name="ViewPermissionUsageActivity" android:exported="true"
            android:targetActivity="com.fit_up.health.capacitor.PermissionsRationaleActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
'''
if 'PermissionsRationaleActivity' not in s: s = s.replace('    </application>', rationale + '    </application>', 1)
open(m, 'w').write(s)
sx = res + '/values/strings.xml'
if os.path.exists(sx):
    x = open(sx).read()
    if 'privacy_policy_url' not in x: x = x.replace('</resources>', '    <string name="privacy_policy_url">file:///android_asset/public/privacy.html</string>\n</resources>'); open(sx, 'w').write(x)
vg = 'android/variables.gradle'
if os.path.exists(vg):
    v = open(vg).read(); v = re.sub(r'minSdkVersion = \d+', 'minSdkVersion = 26', v); v = re.sub(r'compileSdkVersion = \d+', 'compileSdkVersion = 36', v); open(vg, 'w').write(v)
g = 'android/app/build.gradle'; t = open(g).read()
t = re.sub(r'versionCode \d+', f'versionCode {100 + run}', t); t = re.sub(r'versionName "[^"]*"', f'versionName "1.0.{run}"', t)
open(g, 'w').write(t)
# In-app installer for native updates (one tap → Android's Install dialog)
jd = 'android/app/src/main/java/com/fitverse/app'
os.makedirs(jd, exist_ok=True)
for jf in ['ApkInstallerPlugin.java', 'MainActivity.java']: shutil.copy('native/' + jf, os.path.join(jd, jf))
ms = open(m).read()
if 'REQUEST_INSTALL_PACKAGES' not in ms:
    ms = ms.replace('</manifest>', '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n</manifest>'); open(m, 'w').write(ms)
fp = res + '/xml/file_paths.xml'
if os.path.exists(fp):
    x = open(fp).read()
    if '<cache-path' not in x: x = x.replace('</paths>', '    <cache-path name="cache" path="." />\n</paths>'); open(fp, 'w').write(x)
# Health Connect client needs Android Gradle Plugin 8.9.1+
for bg in ['android/build.gradle'] + glob.glob('node_modules/*/android/build.gradle') + glob.glob('node_modules/@*/*/android/build.gradle'):
    try:
        b = open(bg).read(); nb = re.sub(r"com\.android\.tools\.build:gradle:8\.[0-8]\.\d+", 'com.android.tools.build:gradle:8.9.1', b)
        if nb != b: open(bg, 'w').write(nb); print('AGP 8.9.1 ->', bg)
    except Exception: pass
print('patched android, versionCode', 100 + run)
