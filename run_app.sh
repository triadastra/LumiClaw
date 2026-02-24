#!/bin/bash
# run_app.sh — build, sign, and launch LumiAgent.app
# For day-to-day use, prefer auto_update.sh (also kills the running instance first).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/runable/LumiAgent.app"
BINARY_DST="$APP_BUNDLE/Contents/MacOS/LumiAgent"
ENTITLEMENTS="$SCRIPT_DIR/LumiAgent.entitlements"

echo "🚀 Lumi Agent Launcher"
echo "====================="

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "🔨 Building..."
swift build -c debug --package-path "$SCRIPT_DIR"
echo "✅ Build complete"

# ── 2. Copy binary into .app bundle ──────────────────────────────────────────
echo "📦 Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$SCRIPT_DIR/.build/debug/LumiAgent" "$BINARY_DST"
cp "$SCRIPT_DIR/icons/appicon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png" 2>/dev/null || true

# ── 3. Sign ───────────────────────────────────────────────────────────────────
echo "🔐 Signing..."
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" 2>/dev/null || true

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')

if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" \
             --entitlements "$ENTITLEMENTS" \
             "$APP_BUNDLE"
    echo "✅ Signed with Developer cert"
else
    ADHOC_ENT="$SCRIPT_DIR/.build/adhoc.entitlements"
    cat > "$ADHOC_ENT" << 'ENTPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.get-task-allow</key>
    <true/>
</dict>
</plist>
ENTPLIST
    codesign --force --deep --sign - \
             --entitlements "$ADHOC_ENT" \
             "$APP_BUNDLE"
    echo "✅ Signed (ad-hoc, no HealthKit)"
fi

echo "🚀 Launching..."
open -n "$APP_BUNDLE" 2>/dev/null || nohup "$BINARY_DST" </dev/null &>/dev/null &
