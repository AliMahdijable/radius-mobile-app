#!/usr/bin/env bash
# Sets the Android app label to "MyServices Radius" (overrides the
# default 'rad_mysvcs' that Flutter uses from the pubspec name field).
# Run after setup.sh — idempotent, safe to re-run.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "❌ $MANIFEST not found. Run setup.sh first."; exit 1
fi

# Replace android:label="..." inside the <application> tag.
if grep -q 'android:label="rad_mysvcs"' "$MANIFEST"; then
  sed -i.bak 's|android:label="rad_mysvcs"|android:label="MyServices Radius"|' "$MANIFEST"
  rm -f "${MANIFEST}.bak"
  echo "✓ android:label changed to 'MyServices Radius'"
elif grep -q 'android:label="MyServices Radius"' "$MANIFEST"; then
  echo "↻ android:label already 'MyServices Radius' — nothing to do"
else
  echo "⚠ android:label is something unexpected — set manually in $MANIFEST"
fi
