#!/usr/bin/env bash
# Run AFTER setup.sh. Patches iOS Info.plist with:
#   1. NSFaceIDUsageDescription (required for Face ID prompts).
#   2. CFBundleDisplayName = "MyServices Radius" — overrides the Dart
#      project name ('rad_mysvcs') that Flutter uses as the default
#      app label on the home screen.
#
# Without these, the user sees 'rad_mysvcs' under the icon (incident
# 2026-06-02) and Face ID requests silently fail.
set -euo pipefail

PLIST="ios/Runner/Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "❌ $PLIST not found. Run setup.sh first."; exit 1
fi

set_or_add() {
  local key="$1"
  local val="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $val" "$PLIST"
    echo "↻  set $key = $val"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $val" "$PLIST"
    echo "✓  added $key = $val"
  fi
}

set_or_add "NSFaceIDUsageDescription" \
  "نستخدم Face ID للدخول السريع للتطبيق بدون كتابة كلمة المرور."

set_or_add "CFBundleDisplayName" "MyServices Radius"

# Voice search overlay (mic button) — iOS refuses to start
# SFSpeechRecognizer + AVAudioSession without these usage strings.
set_or_add "NSMicrophoneUsageDescription" \
  "نستخدم الميكروفون للبحث الصوتي عن المشتركين والإجراءات."

set_or_add "NSSpeechRecognitionUsageDescription" \
  "نستخدم التعرف على الصوت لتحويل كلامك إلى بحث نصي داخل التطبيق."

echo ""
echo "✅ Done. Rebuild iOS to apply: flutter clean && flutter run -d ios"
