#!/bin/bash
# Builds the Family Budget Flutter project on a Mac.
# Usage:  cd family_budget && bash setup.sh
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/app"

command -v flutter >/dev/null || { echo "Flutter not found. Install it first (see README step 1)."; exit 1; }

if [ ! -d "$APP" ]; then
  echo "==> Creating Flutter project"
  flutter create --org com.familybudget --project-name family_budget --platforms android,ios "$APP"
fi
cd "$APP"

echo "==> Adding packages"
flutter pub add firebase_core firebase_auth cloud_firestore another_telephony shared_preferences intl

echo "==> Copying app code"
rm -f test/widget_test.dart
cp -R "$HERE/src/lib/." lib/
cp -R "$HERE/src/test/." test/
cp "$HERE/src/firestore.rules" .

echo "==> Android manifest (SMS permissions + background receiver)"
RECV=$(grep -rl "class IncomingSmsReceiver" "$HOME/.pub-cache/hosted/pub.dev/" 2>/dev/null | grep another_telephony | sort | tail -1 || true)
if [ -n "$RECV" ]; then
  PKG=$(grep -m1 '^package ' "$RECV" | sed 's/package //; s/;//; s/[[:space:]]//g')
  RECEIVER="$PKG.IncomingSmsReceiver"
else
  RECEIVER="com.shounakmulay.telephony.sms.IncomingSmsReceiver"
fi
echo "    receiver: $RECEIVER"
sed "s#__SMS_RECEIVER__#$RECEIVER#" "$HERE/src/android/AndroidManifest.xml" > android/app/src/main/AndroidManifest.xml

# Firebase needs Android minSdk 23+
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] && sed -i.bak -E 's/minSdk( =|) flutter\.minSdkVersion/minSdk\1 24/' "$f" || true
done

echo "==> iOS deployment target 15.0 (required by Firebase)"
if [ ! -f ios/Podfile ] && [ "$(uname)" = "Darwin" ]; then
  flutter build ios --config-only --no-codesign || true
fi
if grep -q "^# platform :ios" ios/Podfile 2>/dev/null; then
  sed -i.bak "s/^# platform :ios.*/platform :ios, '15.0'/" ios/Podfile
fi
sed -i.bak -E "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/g" ios/Runner.xcodeproj/project.pbxproj

if [ -n "$SKIP_APK" ]; then echo "Project ready in $APP"; exit 0; fi

echo "==> Running parser tests"
flutter test || echo "!! Some tests failed - the app still builds, but tell Claude which ones."

echo "==> Building Android APK"
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "$HERE/FamilyBudget.apk"

echo ""
echo "Done. Android APK: $HERE/FamilyBudget.apk"
echo "For the iPhone: open $APP/ios/Runner.xcworkspace in Xcode (see README step 5)."
