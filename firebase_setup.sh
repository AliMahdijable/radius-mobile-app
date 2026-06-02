#!/usr/bin/env bash
# Copy Firebase config files from v1 to v2. Run AFTER setup.sh.
#
# v1 has GoogleService-Info.plist (iOS) and google-services.json
# (Android) in its repo. Since v2 uses the same Firebase project
# (same bundle id com.mysvcs.radMysvcs), we copy them rather than
# re-downloading from Firebase Console.
#
# Usage:  ./firebase_setup.sh /path/to/v1/mobile-app
set -euo pipefail

V1_DIR="${1:-}"
if [ -z "$V1_DIR" ]; then
  echo "Usage: $0 /path/to/v1/mobile-app"
  echo "Example: $0 ~/projects/mobile-app"
  exit 1
fi

if [ ! -d "$V1_DIR" ]; then
  echo "❌ Directory not found: $V1_DIR"; exit 1
fi

# iOS
IOS_SRC="$V1_DIR/ios/Runner/GoogleService-Info.plist"
IOS_DEST="ios/Runner/GoogleService-Info.plist"
if [ -f "$IOS_SRC" ]; then
  cp "$IOS_SRC" "$IOS_DEST"
  echo "✓ iOS: copied GoogleService-Info.plist"
  echo "  ⚠ You must also add this file to the Xcode project (open"
  echo "    ios/Runner.xcworkspace, drag the file into the Runner group)."
else
  echo "⚠ iOS: $IOS_SRC not found — skip"
fi

# Android
ANDROID_SRC="$V1_DIR/android/app/google-services.json"
ANDROID_DEST="android/app/google-services.json"
if [ -f "$ANDROID_SRC" ]; then
  cp "$ANDROID_SRC" "$ANDROID_DEST"
  echo "✓ Android: copied google-services.json"
else
  echo "⚠ Android: $ANDROID_SRC not found — skip"
fi

echo ""
echo "If files were copied: flutter clean && flutter run -d ios"
echo "If not: the app still launches — NotificationService falls back to"
echo "permission_handler. But notifications won't be delivered via FCM."
