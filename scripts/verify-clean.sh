#!/bin/bash
# Checks that an .ipa carries nothing about whoever built it.
#
#   ./scripts/verify-clean.sh build/export/WattTrace-unsigned.ipa
#
# Every one of these has actually leaked at some point: signing identities are the
# obvious case, but absolute build paths reach the binary twice over — through
# Swift's debug info and #file metadata, and again through the linker's object
# file debug map in the symbol table. The two need different fixes, so both are
# checked here rather than assumed.
set -euo pipefail

IPA="${1:?usage: $0 <path to .ipa>}"
[ -f "$IPA" ] || { echo "no such file: $IPA" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "no .app inside Payload/" >&2; exit 1; }

fail=0
check() { # description, 0 = clean
  if [ "$2" -eq 0 ]; then printf '  ok    %s\n' "$1"
  else printf '  FAIL  %s\n' "$1"; fail=1; fi
}

echo "Checking $(basename "$IPA")"

# Searched for at any depth, not just at the top of the app: an app extension is a
# bundle of its own, and carries its own signature and profile.
[ -n "$(find "$APP" -name _CodeSignature -print -quit)" ] && r=1 || r=0
check "no code signature" $r
[ -n "$(find "$APP" -name embedded.mobileprovision -print -quit)" ] && r=1 || r=0
check "no provisioning profile" $r
[ -n "$(find "$APP" -name embedded.provisionprofile -print -quit)" ] && r=1 || r=0
check "no watch provisioning profile" $r

# Check the actual embedded Watch bundle, not only a standalone target build.
WATCH="$APP/Watch/WattTraceWatch.app"
if [ -f "$WATCH/Info.plist" ]; then
  app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
  watch_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WATCH/Info.plist")
  companion=$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$WATCH/Info.plist")
  watch_executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$WATCH/Info.plist")
  [ "$watch_id" = "$app_id.watchkitapp" ] && [ "$companion" = "$app_id" ] && [ -f "$WATCH/$watch_executable" ] && r=0 || r=1
  check "embedded Watch app and companion bundle identity" $r
  for key in CFBundleShortVersionString CFBundleVersion; do
    app_value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$APP/Info.plist")
    watch_value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$WATCH/Info.plist")
    [ "$app_value" = "$watch_value" ] && r=0 || r=1
    check "Watch $key matches phone" $r
  done
else
  check "embedded Watch app" 1
fi

# A home directory in any file means a build path survived.
if grep -rlq "/Users/" "$APP" 2>/dev/null; then
  echo "  FAIL  no absolute build paths"
  echo "        found in:"
  grep -rl "/Users/" "$APP" 2>/dev/null | sed "s|$WORK|...|" | sed 's/^/          /'
  fail=1
else
  check "no absolute build paths" 0
fi

# Team identifiers are ten alphanumerics; look for the Apple keys that carry them.
if grep -rlq "com.apple.developer.team-identifier\|application-identifier" "$APP" 2>/dev/null; then
  r=1; else r=0; fi
check "no team identifier" $r

echo "  info  bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || echo '?')"
echo "  info  version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo '?')"
echo "  info  extensions: $(find "$APP" -name '*.appex' -type d | wc -l | tr -d ' ')"

[ "$fail" -eq 0 ] || { echo; echo "This build carries identifying data — do not publish it." >&2; exit 1; }
echo
echo "Clean."
