#!/usr/bin/env bash
# Run AFTER setup.sh. Adds the iOS Info.plist usage descriptions that
# Apple requires for biometric + notification permission requests.
# Without these, the request prompts simply don't appear.
set -euo pipefail

PLIST="ios/Runner/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "❌ $PLIST not found. Run setup.sh first."; exit 1
fi

add_key() {
  local key="$1"
  local val="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    echo "↻  $key already present — skipping"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $val" "$PLIST"
    echo "✓  added $key"
  fi
}

# Face ID / biometric reason — shown in the OS prompt
add_key "NSFaceIDUsageDescription" \
  "نستخدم Face ID للدخول السريع للتطبيق بدون كتابة كلمة المرور."

echo ""
echo "✅ Done. Rebuild iOS to apply: flutter clean && flutter run -d ios"
