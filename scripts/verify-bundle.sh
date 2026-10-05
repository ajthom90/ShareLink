#!/usr/bin/env bash
# Checks a built ShareLink.app for the Info.plist, privacy manifest, and
# framework layout Task 1 requires. Source entitlements must contain the App
# Group. Unsigned simulator builds do not embed entitlements. When
# `codesign -d --entitlements :-` succeeds and prints a plist, the app and the
# appex must both include group.com.ajthom90.sharelink.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/verify-bundle.sh <path-to-ShareLink.app>" >&2
  exit 1
fi

APP="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PLIST="${APP}/Info.plist"
APPEX="${APP}/PlugIns/ShareLinkFileProvider.appex"
APPEX_PLIST="${APPEX}/Info.plist"

fail() {
  echo "verify-bundle: $*" >&2
  exit 1
}

plist_get() {
  /usr/libexec/PlistBuddy -c "Print $1" "$2" 2>/dev/null
}

require_eq() {
  local label="$1" key="$2" file="$3" expected="$4" actual
  if ! actual="$(plist_get "$key" "$file")"; then
    fail "${label} missing ${key}"
  fi
  if [[ "$actual" != "$expected" ]]; then
    fail "${label} ${key} is '${actual}', expected '${expected}'"
  fi
}

require_nonempty() {
  local label="$1" key="$2" file="$3" actual
  if ! actual="$(plist_get "$key" "$file")"; then
    fail "${label} missing ${key}"
  fi
  if [[ -z "$actual" ]]; then
    fail "${label} ${key} is empty"
  fi
}

require_suffix() {
  local label="$1" key="$2" file="$3" suffix="$4" actual
  if ! actual="$(plist_get "$key" "$file")"; then
    fail "${label} missing ${key}"
  fi
  if [[ "$actual" != *"$suffix" ]]; then
    fail "${label} ${key} is '${actual}', expected it to end with '${suffix}'"
  fi
}

[[ -f "$APP_PLIST" ]] || fail "missing ${APP_PLIST}"
[[ -f "$APPEX_PLIST" ]] || fail "missing ${APPEX_PLIST}"

require_eq "app" ":ITSAppUsesNonExemptEncryption" "$APP_PLIST" "false"
require_nonempty "app" ":NSLocalNetworkUsageDescription" "$APP_PLIST"
require_eq "app" ":CFBundleURLTypes:0:CFBundleURLSchemes:0" "$APP_PLIST" "sharelink"

marketing="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "${ROOT}/Config/Base.xcconfig" | head -1)"
[[ -n "$marketing" ]] || fail "could not read MARKETING_VERSION from Config/Base.xcconfig"
require_eq "app" ":CFBundleShortVersionString" "$APP_PLIST" "$marketing"
require_eq "app" ":CFBundleIdentifier" "$APP_PLIST" "com.ajthom90.sharelink"

require_eq "appex" ":NSExtension:NSExtensionPointIdentifier" "$APPEX_PLIST" "com.apple.fileprovider-nonui"
require_suffix "appex" ":NSExtension:NSExtensionPrincipalClass" "$APPEX_PLIST" ".FileProviderExtension"
require_eq "appex" ":NSExtension:NSExtensionFileProviderDocumentGroup" "$APPEX_PLIST" "group.com.ajthom90.sharelink"
require_eq "appex" ":ITSAppUsesNonExemptEncryption" "$APPEX_PLIST" "false"
require_eq "appex" ":CFBundleIdentifier" "$APPEX_PLIST" "com.ajthom90.sharelink.FileProvider"

[[ -f "${APP}/PrivacyInfo.xcprivacy" ]] || fail "app is missing PrivacyInfo.xcprivacy"
[[ -f "${APPEX}/PrivacyInfo.xcprivacy" ]] || fail "appex is missing PrivacyInfo.xcprivacy"
plutil -lint "${APP}/PrivacyInfo.xcprivacy" >/dev/null
plutil -lint "${APPEX}/PrivacyInfo.xcprivacy" >/dev/null

nested="$(find "${APP}/PlugIns" -name '*.framework' -print)"
if [[ -n "$nested" ]]; then
  fail "nested framework under PlugIns: ${nested}"
fi
[[ -d "${APP}/Frameworks/AMSMB2.framework" ]] || fail "missing Frameworks/AMSMB2.framework"

for entitlements in \
  "${ROOT}/App/ShareLink/ShareLink.entitlements" \
  "${ROOT}/Extensions/FileProvider/FileProvider.entitlements"
do
  [[ -f "$entitlements" ]] || fail "missing source entitlements ${entitlements}"
  require_eq "$(basename "$entitlements")" ":com.apple.security.application-groups:0" "$entitlements" "group.com.ajthom90.sharelink"
done

# Writes a plist to dest and returns 0 when codesign prints embedded entitlements.
# Unsigned simulator builds produce no plist; that path stays source-only.
has_embedded_entitlements_plist() {
  local target="$1" dest="$2" ent
  if ! ent="$(codesign -d --entitlements :- "$target" 2>/dev/null)"; then
    return 1
  fi
  if [[ "$ent" != *"<plist"* && "$ent" != bplist* ]]; then
    return 1
  fi
  printf '%s' "$ent" > "$dest"
  plutil -lint "$dest" >/dev/null 2>&1
}

require_embedded_app_group() {
  local label="$1" file="$2" i=0 value found=0
  while value="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:${i}" "$file" 2>/dev/null)"; do
    if [[ "$value" == "group.com.ajthom90.sharelink" ]]; then
      found=1
      break
    fi
    i=$((i + 1))
  done
  if [[ "$found" -ne 1 ]]; then
    fail "${label} embedded entitlements do not contain group.com.ajthom90.sharelink"
  fi
}

ent_tmp="$(mktemp -d)"
trap 'rm -rf "$ent_tmp"' EXIT
if has_embedded_entitlements_plist "$APP" "${ent_tmp}/app.plist"; then
  require_embedded_app_group "app" "${ent_tmp}/app.plist"
  if ! has_embedded_entitlements_plist "$APPEX" "${ent_tmp}/appex.plist"; then
    fail "appex embedded entitlements plist missing"
  fi
  require_embedded_app_group "appex" "${ent_tmp}/appex.plist"
fi
