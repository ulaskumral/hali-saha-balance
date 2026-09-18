#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK PATH içinde bulunamadı." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d android || ! -d ios ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  flutter create --platforms=android,ios --project-name hali_saha_balance "$TMP/scaffold"
  [[ -d android ]] || cp -R "$TMP/scaffold/android" "$ROOT/android"
  [[ -d ios ]] || cp -R "$TMP/scaffold/ios" "$ROOT/ios"
  [[ -f .metadata ]] || cp "$TMP/scaffold/.metadata" "$ROOT/.metadata"
fi

# Current plugins in pubspec require Android SDK 24+ and iOS 14+.
if [[ -f android/app/build.gradle.kts ]]; then
  sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts || true
  rm -f android/app/build.gradle.kts.bak
fi
if [[ -f ios/Podfile ]]; then
  python - <<'PY'
from pathlib import Path
p = Path('ios/Podfile')
s = p.read_text()
if "platform :ios" in s:
    import re
    s = re.sub(r"#?\s*platform :ios, '[^']+'", "platform :ios, '14.0'", s, count=1)
else:
    s = "platform :ios, '14.0'\n" + s
p.write_text(s)
PY
fi
if [[ -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  python - <<'PY'
from pathlib import Path
import re
p = Path('ios/Runner.xcodeproj/project.pbxproj')
s = p.read_text()
s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', s)
p.write_text(s)
PY
fi
if [[ -f ios/Runner/Info.plist ]]; then
  python - <<'PY'
from pathlib import Path
import plistlib
p = Path('ios/Runner/Info.plist')
with p.open('rb') as f:
    data = plistlib.load(f)
data.setdefault('NSPhotoLibraryUsageDescription', 'Oyuncu profil fotoğrafı seçmek için fotoğraf arşivine erişim gerekir.')
with p.open('wb') as f:
    plistlib.dump(data, f, sort_keys=False)
PY
fi

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
