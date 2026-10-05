#!/usr/bin/env bash
# Signs a simulator build and runs ShareLinkUITests against Docker Samba.
#
# Managed config is written two ways, and both use the same dictionary
# (Host 127.0.0.1, Port 1445, Share signed, Username testuser, DisplayName "Samba Test"):
#   1. `simctl spawn defaults write` after the app is installed.
#   2. The UI test launches ShareLink with -SLE2EManagedConfig. xcodebuild test can
#      reinstall the app and wipe the defaults domain, so the DEBUG launch argument
#      in ShareLinkApp.launchManagedConfig() is what the test relies on.
#
# The managed server id is stable, so a password left in the simulator keychain
# by an earlier run signs the share in before the sheet can appear. Uninstall
# does not clear that keychain. The script resets it after uninstall.
#
# Uninstall also leaves the File Provider domain behind (materialized items,
# fileproviderd's domain database, and the App Group metadata index). The script
# removes that state for com.ajthom90.sharelink.FileProvider. Set E2E_ERASE=1
# to `simctl erase` the simulator before boot when a full wipe is required.
# That option is off by default.
#
# The UI test creates a folder and leaves Files' default name in place. Before
# the test the script removes leftover "untitled folder*" directories and
# records the share's top-level names. Afterwards it requires a new directory
# of any name, which is the proof that createItem reached Samba.
#
# Exits 0 and prints SKIP when 127.0.0.1:1445 is not accepting TCP.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BEFORE_DIRS=""
AFTER_DIRS=""

on_exit() {
  if [[ -n "${BEFORE_DIRS:-}" ]]; then rm -f "$BEFORE_DIRS"; fi
  if [[ -n "${AFTER_DIRS:-}" ]]; then rm -f "$AFTER_DIRS"; fi
}
trap on_exit EXIT

# `simctl spawn` cannot disable fileproviderd (not permitted). The daemon is a
# host process whose open files include this device's data directory.
fileproviderd_pids() {
  local udid="$1"
  local pid
  for pid in $(pgrep -f 'FileProvider.framework/Support/fileproviderd' || true); do
    if lsof -p "$pid" 2>/dev/null | grep -q "$udid"; then
      printf '%s\n' "$pid"
    fi
  done
}

stop_fileproviderd() {
  local udid="$1"
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -9 "$pid" 2>/dev/null || true
  done < <(fileproviderd_pids "$udid")
}

# Directories only. `ls -1` (printed separately) also lists files such as hello.txt.
server_directories() {
  docker compose -f Tests/Samba/docker-compose.yml exec -T samba \
    sh -c 'cd /shares/signed && for n in *; do if [ -d "$n" ]; then printf "%s\n" "$n"; fi; done' \
    | tr -d '\r' | LC_ALL=C sort
}

# fileproviderd keeps the domain after the app is uninstalled. Stop it, delete
# this provider's records, then let launchd start it again.
clear_file_provider_state() {
  local udid="$1"
  local data="${HOME}/Library/Developer/CoreSimulator/Devices/${udid}/data"
  local fp="${data}/Library/Application Support/FileProvider"
  local provider="${fp}/com.ajthom90.sharelink.FileProvider"
  local bundle="com.ajthom90.sharelink.FileProvider"

  local fpfs
  # stdout and stderr: fileproviderctl's root line is `<FPFS>/<uuid>`.
  fpfs="$(xcrun simctl spawn "$udid" fileproviderctl dump "$bundle" 2>&1 | sed -nE 's/.*<FPFS>\/([0-9A-Fa-f-]{36}).*/\1/p' | head -1 || true)"

  # Launchd restarts the daemon. Stop it, delete, then stop the replacement so
  # a respawn cannot rewrite the database from the old mapping.
  stop_fileproviderd "$udid"
  sleep 0.3

  remove_domain_files() {
    if [[ -n "$fpfs" ]]; then
      rm -rf "${data}/Library/CloudStorage/${fpfs}"
      local db
      for db in "$fp"/*/database/db; do
        [[ -f "$db" ]] || continue
        if strings "$db" | grep -q "$fpfs"; then
          rm -rf "$(dirname "$(dirname "$db")")"
        fi
      done
    fi
    rm -rf "$provider"
  }
  remove_domain_files
  stop_fileproviderd "$udid"
  remove_domain_files
  if [[ -n "$fpfs" ]]; then
    echo "Removed File Provider domain storage ${fpfs}"
  else
    echo "File Provider dump did not name an FPFS root; removing the provider directory and App Group index" >&2
  fi

  local meta group_container=""
  if [[ -d "${data}/Containers/Shared/AppGroup" ]]; then
    for meta in "${data}/Containers/Shared/AppGroup"/*/.com.apple.mobile_container_manager.metadata.plist; do
      [[ -f "$meta" ]] || continue
      if plutil -p "$meta" | grep -q 'group.com.ajthom90.sharelink'; then
        group_container="$(dirname "$meta")"
        break
      fi
    done
  fi
  if [[ -n "$group_container" ]]; then
    rm -rf "${group_container}/Domains" "${group_container}/File Provider Storage"
    echo "Removed App Group domain index"
  fi
}

if ! nc -z -G 2 127.0.0.1 1445 >/dev/null 2>&1; then
  echo "SKIP: 127.0.0.1:1445 is not accepting TCP connections."
  echo "Start Samba with: docker compose -f Tests/Samba/docker-compose.yml up -d --build"
  exit 0
fi

UDID="$(
  python3 - <<'PY'
import json, re, subprocess, sys
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
data = json.loads(raw)
candidates = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if name.startswith("iPad Pro"):
            rank = 0
        elif name.startswith("iPad Air"):
            rank = 1
        elif name.startswith("iPad"):
            rank = 2
        else:
            continue
        candidates.append((version, rank, name, device["udid"]))
if not candidates:
    print("no available iPad simulator", file=sys.stderr)
    sys.exit(1)
# Newest iOS, then iPad Pro, then iPad Air. Within that rank, the later name
# (13-inch before 11-inch) wins.
candidates.sort(key=lambda item: (-item[0][0], -item[0][1], item[1], item[2]))
best_version = candidates[0][0]
best_rank = candidates[0][1]
tied = [item for item in candidates if item[0] == best_version and item[1] == best_rank]
tied.sort(key=lambda item: item[2], reverse=True)
chosen = tied[0]
print(f"simulator: {chosen[2]} iOS {chosen[0][0]}.{chosen[0][1]} {chosen[3]}", file=sys.stderr)
print(chosen[3])
PY
)"

echo "Using simulator ${UDID}"
if [[ "${E2E_ERASE:-0}" == "1" ]]; then
  echo "E2E_ERASE=1: erasing simulator ${UDID}"
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl erase "$UDID"
fi
# This Xcode takes the device first: `bootstatus <device> -b` boots if needed and waits.
xcrun simctl bootstatus "$UDID" -b

xcrun simctl terminate "$UDID" com.ajthom90.sharelink >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" com.apple.DocumentsApp >/dev/null 2>&1 || true
# The extension keeps running after the app terminates.
pkill -f "${UDID}/data/Containers/.*ShareLinkFileProvider" >/dev/null 2>&1 || true
# Dump the domain while fileproviderd still has it, then delete its records.
clear_file_provider_state "$UDID"
xcrun simctl uninstall "$UDID" com.ajthom90.sharelink >/dev/null 2>&1 || true
xcrun simctl keychain "$UDID" reset

docker compose -f Tests/Samba/docker-compose.yml exec -T samba \
  sh -c 'printf hi > /shares/signed/hello.txt && chown testuser /shares/signed/hello.txt && cd /shares/signed && for d in untitled\ folder*; do if [ -d "$d" ]; then rm -rf "$d"; fi; done'

echo "Server top-level names before the test:"
docker compose -f Tests/Samba/docker-compose.yml exec -T samba ls -1 /shares/signed | tr -d '\r'
BEFORE_DIRS="$(mktemp)"
server_directories > "$BEFORE_DIRS"

xcodegen generate

DERIVED="${ROOT}/build/DerivedData-e2e"
RESULT="${DERIVED}/Logs/Test/ShareLinkUITests.xcresult"
rm -rf "$RESULT"
mkdir -p "${DERIVED}/Logs/Test"

echo "Building ShareLink for testing with signing allowed..."
xcodebuild build-for-testing \
  -project ShareLink.xcodeproj \
  -scheme ShareLink \
  -destination "id=${UDID}" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES

require_group() {
  local label="$1"
  local file="$2"
  if ! plutil -p "$file" | grep -q 'group.com.ajthom90.sharelink'; then
    echo "${label} simulated entitlements are missing group.com.ajthom90.sharelink (${file})" >&2
    plutil -p "$file" >&2 || true
    exit 1
  fi
  echo "${label} App Group present: ${file}"
}

collect_xcents() {
  local pattern="$1"
  find "$DERIVED/Build/Intermediates.noindex" -name "$pattern" -path '*iphonesimulator*' -print 2>/dev/null || true
}

check_product() {
  local label="$1"
  local pattern="$2"
  local binary="$3"
  local found=0
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    found=1
    require_group "$label" "$file"
  done < <(collect_xcents "$pattern")
  if [[ "$found" -eq 1 ]]; then
    return 0
  fi

  echo "no ${pattern} under Intermediates.noindex; trying __TEXT,__entitlements on ${binary}" >&2
  local extracted="${DERIVED}/Logs/Test/${label}-entitlements.plist"
  rm -f "$extracted"
  if [[ -f "$binary" ]] && segedit "$binary" -extract __TEXT __entitlements "$extracted" 2>/dev/null && [[ -s "$extracted" ]] && plutil -lint "$extracted" >/dev/null 2>&1; then
    require_group "$label" "$extracted"
    return 0
  fi

  echo "App Group group.com.ajthom90.sharelink was not found for ${label}." >&2
  echo "xcent files:" >&2
  find "$DERIVED/Build" -name '*.xcent' -print >&2 || true
  if [[ -f "$binary" ]]; then
    echo "codesign entitlements (empty on simulator is expected):" >&2
    codesign -d --entitlements - "$binary" >&2 || true
  fi
  exit 1
}

APP="${DERIVED}/Build/Products/Debug-iphonesimulator/ShareLink.app"
check_product "app" "*.app-Simulated.xcent" "${APP}/ShareLink"
check_product "appex" "*.appex-Simulated.xcent" "${APP}/PlugIns/ShareLinkFileProvider.appex/ShareLinkFileProvider"

echo "Installing ShareLink and seeding managed configuration..."
xcrun simctl install "$UDID" "$APP"
# Best-effort. The UI test passes -SLE2EManagedConfig because this domain may not
# survive the test runner's reinstall. See ShareLinkApp.launchManagedConfig().
if ! xcrun simctl spawn "$UDID" defaults write com.ajthom90.sharelink com.apple.configuration.managed -dict \
  Host 127.0.0.1 Port 1445 Share signed Username testuser DisplayName "Samba Test"; then
  echo "warning: simctl defaults write failed; the test will use -SLE2EManagedConfig" >&2
fi

set +e
xcodebuild test \
  -project ShareLink.xcodeproj \
  -scheme ShareLink \
  -destination "id=${UDID}" \
  -derivedDataPath "$DERIVED" \
  -only-testing:ShareLinkUITests \
  -allowProvisioningUpdates \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=YES
test_status=$?
set -e

folder_status=0
AFTER_DIRS="$(mktemp)"
server_directories > "$AFTER_DIRS" || true
NEW_DIRS="$(comm -13 "$BEFORE_DIRS" "$AFTER_DIRS" || true)"
if [[ -z "$(printf '%s' "$NEW_DIRS" | tr -d '[:space:]')" ]]; then
  echo "no new directory appeared on the Samba server (/shares/signed)" >&2
  echo "directories before:" >&2
  cat "$BEFORE_DIRS" >&2 || true
  echo "listing after:" >&2
  docker compose -f Tests/Samba/docker-compose.yml exec -T samba ls -1 /shares/signed >&2 || true
  folder_status=1
else
  echo "New server directory:"
  printf '%s\n' "$NEW_DIRS"
fi

if [[ "$test_status" -ne 0 || "$folder_status" -ne 0 ]]; then
  echo "--- ShareLinkFileProvider logs (last 10 minutes, last 200 lines) ---"
  xcrun simctl spawn "$UDID" log show --last 10m --style compact \
    --predicate 'process == "ShareLinkFileProvider" OR subsystem == "com.ajthom90.sharelink"' \
    | tail -n 200 || true
  echo "--- DiagnosticReports from the last hour ---"
  find "${HOME}/Library/Logs/DiagnosticReports" -name 'ShareLinkFileProvider*' -mmin -60 -print || true
  group_container="$(xcrun simctl get_app_container "$UDID" com.ajthom90.sharelink group.com.ajthom90.sharelink 2>/dev/null || true)"
  if [[ -n "$group_container" && -f "${group_container}/diagnostics.log" ]]; then
    echo "--- App Group diagnostics.log (last 80 lines) ---"
    tail -n 80 "${group_container}/diagnostics.log" || true
  fi
  echo "xcresult: ${RESULT}"
  exit 1
fi

echo "PASS: simulator File Provider end-to-end test"
echo "xcresult: ${RESULT}"
