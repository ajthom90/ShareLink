#!/usr/bin/env bash
# Archive ShareLink and upload it to App Store Connect / TestFlight.
#   --dry-run        archive + export locally (destination=export) without uploading
#   --internal-only  mark the build for internal TestFlight testing only
#
# SHARELINK_LOCAL_XCCONFIG overrides the Team ID file (default Config/Local.xcconfig).
# The Team ID is injected into build/ExportOptions.plist, never into scripts/ExportOptions.plist.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

DRY_RUN=0; INTERNAL_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --internal-only) INTERNAL_ONLY=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

LOCAL_XCCONFIG="${SHARELINK_LOCAL_XCCONFIG:-Config/Local.xcconfig}"
if [[ ! -f "$LOCAL_XCCONFIG" ]]; then
  if [[ "$LOCAL_XCCONFIG" == "Config/Local.xcconfig" ]]; then
    echo "Missing Config/Local.xcconfig (copy from Config/Local.xcconfig.example)" >&2
  else
    echo "Missing Config/Local.xcconfig (${LOCAL_XCCONFIG}; copy from Config/Local.xcconfig.example)" >&2
  fi
  exit 1
fi
TEAM_ID=$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]{10}).*/\1/p' "$LOCAL_XCCONFIG" | head -1)
[[ -n "$TEAM_ID" ]] || { echo "DEVELOPMENT_TEAM not set in ${LOCAL_XCCONFIG}" >&2; exit 1; }

AUTH_ARGS=()
if [[ -f .env ]]; then set -a; . ./.env; set +a; fi
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
elif [[ $DRY_RUN -eq 0 ]]; then
  echo "Set ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH in .env (or sign in to Xcode and accept interactive auth)" >&2
fi

./scripts/check-secrets.sh
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean; commit first" >&2; exit 1; }

xcodegen generate
BUILD_NUMBER=$(( $(git rev-list --count HEAD) + ${BUILD_OFFSET:-0} ))
VERSION=$(sed -nE 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*(.*)$/\1/p' Config/Base.xcconfig)
ARCHIVE="build/ShareLink-$VERSION-$BUILD_NUMBER.xcarchive"
rm -rf "$ARCHIVE" build/export

xcodebuild -project ShareLink.xcodeproj -scheme ShareLink -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates "${AUTH_ARGS[@]}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

APP="$ARCHIVE/Products/Applications/ShareLink.app"
./scripts/verify-bundle.sh "$APP"
if find "$APP/PlugIns" -name '*.framework' -maxdepth 3 | grep -q .; then
  echo "ERROR: nested frameworks inside the extension; App Store will reject this build" >&2; exit 1
fi
[[ -d "$APP/Frameworks/AMSMB2.framework" ]] || { echo "ERROR: AMSMB2.framework not embedded (LGPL dynamic-link requirement)" >&2; exit 1; }

OPTS=build/ExportOptions.plist
cp scripts/ExportOptions.plist "$OPTS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTS"
[[ $INTERNAL_ONLY -eq 1 ]] && /usr/libexec/PlistBuddy -c "Set :testFlightInternalTestingOnly true" "$OPTS"
[[ $DRY_RUN -eq 1 ]] && /usr/libexec/PlistBuddy -c "Set :destination export" "$OPTS"

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" \
  -exportPath build/export -allowProvisioningUpdates "${AUTH_ARGS[@]}"

if [[ $DRY_RUN -eq 0 ]]; then
  TAG="v$VERSION-$BUILD_NUMBER"
  git tag -a "$TAG" -m "TestFlight build $VERSION ($BUILD_NUMBER)"
  ./scripts/package-third-party-sources.sh build/
  echo "Uploaded $VERSION ($BUILD_NUMBER). Next: git push origin $TAG && gh release create $TAG build/third-party-sources-$VERSION.tar.gz --prerelease --notes 'TestFlight build'"
else
  echo "Dry run complete: build/export"
fi
