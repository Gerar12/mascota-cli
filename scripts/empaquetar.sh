#!/bin/sh
# Compila Mascota.app y la instala en ~/Applications.
set -eu
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
cd "$RAIZ"
swift build -c release
APP="$RAIZ/.build/Mascota.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Mascota "$APP/Contents/MacOS/Mascota"
mkdir -p "$APP/Contents/Resources"
python3 "$RAIZ/scripts/icono.py" "$APP/Contents/Resources/Mascota.icns" || echo "Sin ícono (falta Pillow)"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.gcoder.mascota</string>
  <key>CFBundleName</key><string>Mascota</string>
  <key>CFBundleExecutable</key><string>Mascota</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>VERSION_COMPILACION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>Mascota</string>
  <key>NSAppleEventsUsageDescription</key><string>Para llevarte a la terminal de Ghostty de cada sesión.</string>
</dict></plist>
EOF
# Versión nueva en cada compilación: así macOS refresca el ícono en el Centro de notificaciones.
sed -i '' "s/VERSION_COMPILACION/$(date +%Y%m%d%H%M%S)/" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
mkdir -p "$HOME/Applications"
pkill -x Mascota 2>/dev/null || true
rm -rf "$HOME/Applications/Mascota.app"
cp -R "$APP" "$HOME/Applications/Mascota.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Mascota.app" 2>/dev/null || true
open "$HOME/Applications/Mascota.app"
echo "Mascota instalada en ~/Applications/Mascota.app"
