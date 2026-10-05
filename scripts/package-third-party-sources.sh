#!/usr/bin/env bash
# Write <outdir>/third-party-sources-<MARKETING_VERSION>.tar.gz containing the
# AMSMB2 and GRDB.swift sources pinned in Packages/ShareLinkKit/Package.resolved,
# including git submodules (libsmb2 ships inside AMSMB2). VCS metadata is removed.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "usage: $0 <outdir>" >&2
  exit 2
fi

OUTDIR="$1"
mkdir -p "$OUTDIR"

RESOLVED="Packages/ShareLinkKit/Package.resolved"
if [[ ! -f "$RESOLVED" ]]; then
  (cd Packages/ShareLinkKit && swift package resolve)
fi

VERSION=$(sed -nE 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' Config/Base.xcconfig | head -1)
if [[ -z "${VERSION}" ]]; then
  echo "MARKETING_VERSION not found in Config/Base.xcconfig" >&2
  exit 1
fi

eval "$(python3 - "$RESOLVED" <<'PY'
import json, shlex, sys
data = json.load(open(sys.argv[1]))
found = {}
for pin in data["pins"]:
    version = (pin.get("state") or {}).get("version")
    if not version:
        continue
    found[pin["identity"].lower()] = (version, pin["location"])
for ident, prefix in (("amsmb2", "AMSMB2"), ("grdb.swift", "GRDB")):
    if ident not in found:
        sys.stderr.write(f"Package.resolved has no version pin for {ident}\n")
        sys.exit(1)
    version, url = found[ident]
    print(f"{prefix}_VERSION={shlex.quote(version)}")
    print(f"{prefix}_URL={shlex.quote(url)}")
PY
)"

# Package.resolved records a semantic version. Some tags keep a leading "v"
# (GRDB.swift 7.11.1 is the tag v7.11.1).
resolve_tag() {
  local url="$1" version="$2"
  local tags
  tags=$(git ls-remote --tags "$url")
  if printf '%s\n' "$tags" | grep -q "refs/tags/${version}$"; then
    printf '%s\n' "$version"
  elif printf '%s\n' "$tags" | grep -q "refs/tags/v${version}$"; then
    printf '%s\n' "v${version}"
  else
    echo "no tag ${version} or v${version} in ${url}" >&2
    return 1
  fi
}

AMSMB2_TAG=$(resolve_tag "$AMSMB2_URL" "$AMSMB2_VERSION")
GRDB_TAG=$(resolve_tag "$GRDB_URL" "$GRDB_VERSION")

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/sharelink-sources.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

export GIT_TERMINAL_PROMPT=0
git clone --depth 1 --branch "$AMSMB2_TAG" --recurse-submodules --shallow-submodules "$AMSMB2_URL" "$WORKDIR/AMSMB2"
git clone --depth 1 --branch "$GRDB_TAG" --recurse-submodules --shallow-submodules "$GRDB_URL" "$WORKDIR/GRDB.swift"

# Finish the find before deleting, so removing a .git directory cannot race the walk.
gitlist=$(mktemp)
find "$WORKDIR" -name .git > "$gitlist"
while IFS= read -r path; do
  rm -rf "$path"
done < "$gitlist"
rm -f "$gitlist"

ARCHIVE="${OUTDIR%/}/third-party-sources-${VERSION}.tar.gz"
rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$WORKDIR" .
echo "Wrote ${ARCHIVE}"
