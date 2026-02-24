#!/bin/bash
# auto_update.sh — build, sign, and relaunch LumiAgent.app
# Run this whenever you want to push code changes into the running app.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/runable/LumiAgent.app"
BINARY_DST="$APP_BUNDLE/Contents/MacOS/LumiAgent"
BINARY_SRC="$SCRIPT_DIR/.build/debug/LumiAgent"
ENTITLEMENTS="$SCRIPT_DIR/LumiAgent.entitlements"

echo "🔄 LumiAgent Auto-Update"
echo "========================"

# ── 1. Kill running instance ──────────────────────────────────────────────────
if pgrep -x "LumiAgent" > /dev/null 2>&1; then
    echo "⏹  Stopping running LumiAgent..."
    pkill -x "LumiAgent" || true
    sleep 0.6
fi

# ── 2. Build ──────────────────────────────────────────────────────────────────
echo "🔨 Building..."
swift build -c debug --package-path "$SCRIPT_DIR"
echo "✅ Build complete"

# ── 3. Scaffold bundle if needed, then copy binary ───────────────────────────
echo "📦 Updating bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Write Info.plist if missing or stale
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LumiAgent</string>
    <key>CFBundleIdentifier</key>
    <string>com.lumiagent.app</string>
    <key>CFBundleName</key>
    <string>LumiAgent</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHealthShareUsageDescription</key>
    <string>Lumi reads your Apple Health data to display metrics and provide AI-powered wellness insights.</string>
    <key>NSHealthUpdateUsageDescription</key>
    <string>Lumi does not write any data to Apple Health.</string>
</dict>
</plist>
PLIST

cp "$BINARY_SRC" "$BINARY_DST"

# Copy app icon to Resources
cp "$SCRIPT_DIR/icons/appicon.png" "$APP_BUNDLE/Contents/Resources/AppIcon.png" 2>/dev/null || true

# ── 4. Sign ───────────────────────────────────────────────────────────────────
# Prefer a real Apple Development identity (needed for HealthKit via launchd).
# If none exists, fall back to ad-hoc and launch the binary directly to bypass
# launchd's strict entitlement-certificate check.
echo "🔐 Signing..."
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

# Reset LaunchServices cache so it picks up the fresh Info.plist / bundle ID
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_BUNDLE" 2>/dev/null || true

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep -o '"Apple Development[^"]*"' | head -1 | tr -d '"')

if [ -n "$IDENTITY" ]; then
    echo "   Using certificate: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" \
             --entitlements "$ENTITLEMENTS" \
             "$APP_BUNDLE"
else
    echo "   No Developer cert found — ad-hoc signing (no HealthKit)"
    # HealthKit entitlements require a real Developer cert.
    # Sign with only get-task-allow for ad-hoc builds.
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
fi

echo "🚀 Launching..."
# open -n works with proper Developer cert signing; ad-hoc needs direct binary launch.
open -n "$APP_BUNDLE" 2>/dev/null || nohup "$BINARY_DST" </dev/null &>/dev/null &

echo "✅ Done"
