#!/usr/bin/env bash
# Initial setup. Run ONCE on Mac after cloning. Scaffolds ios/ + android/
# folders without touching lib/.
set -euo pipefail

ORG="com.mysvcs"
NAME="rad_mysvcs"

if [ ! -f pubspec.yaml ]; then
  echo "❌ Run from inside mobile-app-v2/"; exit 1
fi

echo "🔧 Scaffolding ios/ + android/ …"
flutter create --org "$ORG" --project-name "$NAME" \
  --platforms=ios,android --no-overwrite .

echo "📦 flutter pub get …"
flutter pub get

echo ""
echo "✅ Done. Run:  flutter run -d ios   (or -d android)"
