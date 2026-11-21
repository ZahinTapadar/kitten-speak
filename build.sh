#!/bin/bash
# Builds KittenSpeak.app, installs it to ~/Applications and registers the right-click Service.
set -euo pipefail
cd "$(dirname "$0")"
[ -x .venv/bin/python ] || { uv venv -p 3.12 .venv && uv pip install -p .venv -r requirements.txt && uv pip install -p .venv --no-deps "kittenml @ git+https://github.com/KittenML/KittenTTS" "en_core_web_sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"; }

APP=build/KittenSpeak.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 KittenSpeak.swift -o "$APP/Contents/MacOS/KittenSpeak"
sed "s#__PYTHON__#$PWD/.venv/bin/python#" Info.plist > "$APP/Contents/Info.plist"
cp engine.py "$APP/Contents/Resources/"
codesign --force -s - "$APP"

pkill -x KittenSpeak || true
mkdir -p ~/Applications && rm -rf ~/Applications/KittenSpeak.app && cp -R "$APP" ~/Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/KittenSpeak.app
/System/Library/CoreServices/pbs -update
open ~/Applications/KittenSpeak.app
echo "Installed. Select text anywhere → right-click → Services → Speak with KittenSpeak"
