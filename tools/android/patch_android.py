#!/usr/bin/env python3
"""Patches the generated Android project (run from app/ after `flutter create`):
app name, internet + in-app update permissions, the updater's file provider,
a fixed signing key (so each new APK installs as an update), and desugaring."""
import os, re, shutil, sys

here = os.path.dirname(os.path.abspath(__file__))
man = 'android/app/src/main/AndroidManifest.xml'
s = open(man).read()
s = s.replace('android:label="hifz_academy"', 'android:label="Hifz Academy"')
perms = ('    <uses-permission android:name="android.permission.INTERNET"/>\n'
         '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n'
         '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n')
if 'REQUEST_INSTALL_PACKAGES' not in s:
    s = re.sub(r'(<manifest[^>]*>\n)', lambda m: m.group(1) + perms, s, count=1)
provider = '''        <provider
            android:name="sk.fourq.otaupdate.OtaUpdateFileProvider"
            android:authorities="${applicationId}.ota_update_provider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/filepaths" />
        </provider>
'''
if 'OtaUpdateFileProvider' not in s:
    s = s.replace('    </application>', provider + '    </application>', 1)
# "Recite to me": let the app find the phone's speech recogniser (Android 11+).
speech = ('        <intent>\n'
          '            <action android:name="android.speech.RecognitionService"/>\n'
          '        </intent>\n')
if 'RecognitionService' not in s:
    if '<queries>' in s:
        s = s.replace('<queries>\n', '<queries>\n' + speech, 1)
    else:
        s = s.replace('</manifest>', '    <queries>\n' + speech + '    </queries>\n</manifest>', 1)
open(man, 'w').write(s)
os.makedirs('android/app/src/main/res/xml', exist_ok=True)
shutil.copy(os.path.join(here, 'filepaths.xml'), 'android/app/src/main/res/xml/filepaths.xml')
shutil.copy(os.path.join(here, 'hifz.keystore'), 'android/app/fixed.keystore')

for f in ['android/app/build.gradle.kts', 'android/app/build.gradle']:
    if not os.path.exists(f):
        continue
    g = open(f).read()
    if 'fixed.keystore' in g:
        break
    kts = f.endswith('.kts')
    block = ('''
    signingConfigs {
        getByName("debug") {
            storeFile = file("fixed.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
''' if kts else '''
    signingConfigs {
        debug {
            storeFile file("fixed.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
''')
    g = re.sub(r'^android \{\n', lambda m: m.group(0) + block, g, count=1, flags=re.M)
    # The recorder used by the recitation teacher needs Android 7 (API 24) or newer.
    g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24').replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    if kts:
        g = re.sub(r'compileOptions \{\n', lambda m: m.group(0) + '        isCoreLibraryDesugaringEnabled = true\n', g, count=1)
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    else:
        g = re.sub(r'compileOptions \{\n', lambda m: m.group(0) + '        coreLibraryDesugaringEnabled true\n', g, count=1)
        g += '\ndependencies {\n    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.4"\n}\n'
    open(f, 'w').write(g)
    print('patched', f)
    break
else:
    sys.exit('no app build.gradle found')
