#!/bin/sh
# Xcode Cloud post-clone: the XcodeGen project and Local.xcconfig are git-ignored.
# Xcode Cloud runs this from ci_scripts/ with CI_PRIMARY_REPOSITORY_PATH set.
# Automatic package resolution is off, so the project-level Package.resolved
# must exist before xcodebuild. Its pins match Packages/ShareLinkKit/Package.resolved.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
else
  cd "$SCRIPT_DIR/.."
fi

# Xcode Cloud images have Homebrew, but it is not always on PATH.
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
xcodegen --version

# Team ID stays in the workflow secret. Never print SHARELINK_DEVELOPMENT_TEAM.
local_config="Config/Local.xcconfig"
( umask 077; : > "$local_config" )
if [ -n "${SHARELINK_DEVELOPMENT_TEAM:-}" ]; then
  printf 'DEVELOPMENT_TEAM = %s\n' "$SHARELINK_DEVELOPMENT_TEAM" >> "$local_config"
else
  echo "warning: SHARELINK_DEVELOPMENT_TEAM is unset; Config/Local.xcconfig has no DEVELOPMENT_TEAM. Xcode Cloud cloud signing may supply the team." >&2
fi
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  printf 'CURRENT_PROJECT_VERSION = %s\n' "$CI_BUILD_NUMBER" >> "$local_config"
fi

xcodegen generate

resolved_dir="ShareLink.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$resolved_dir"
cp "Packages/ShareLinkKit/Package.resolved" "$resolved_dir/Package.resolved"

scheme="ShareLink.xcodeproj/xcshareddata/xcschemes/ShareLink.xcscheme"
if [ ! -f "$scheme" ]; then
  echo "error: shared scheme missing at $scheme" >&2
  exit 1
fi
