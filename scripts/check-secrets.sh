#!/usr/bin/env bash
# Fails if tracked or about-to-be-committed files contain secrets or org-specific strings.
# Org-specific patterns live in the git-ignored .proprietary-patterns (one ERE per line).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

patterns=(
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}'
  'teamID</key>[[:space:]]*<string>[A-Z0-9]{10}'
)
if [[ -f .proprietary-patterns ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    patterns+=("$line")
  done < .proprietary-patterns
fi

status=0
while IFS= read -r -d '' file; do
  [[ "$file" == "scripts/check-secrets.sh" ]] && continue
  [[ -f "$file" ]] || continue
  for p in "${patterns[@]}"; do
    if grep -nIiE -- "$p" "$file" >/dev/null 2>&1; then
      echo "check-secrets: pattern matched in $file: $p" >&2
      status=1
    fi
  done
done < <(git ls-files -z --cached --others --exclude-standard)

if git ls-files --cached --others --exclude-standard | grep -E '\.(p8|p12|mobileprovision)$|(^|/)Local\.xcconfig$|\.local\.json$|(^|/)\.env$'; then
  echo "check-secrets: forbidden file is tracked" >&2
  status=1
fi
exit $status
