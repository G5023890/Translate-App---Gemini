#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# High-signal patterns for common API keys/tokens.
PATTERNS=(
  'AIza[0-9A-Za-z\-_]{35}'
  'sk-[A-Za-z0-9]{20,}'
  'ghp_[A-Za-z0-9]{30,}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
)

# Skip generated/vendor folders.
EXCLUDES=(
  ':(exclude).git/*'
  ':(exclude).build/*'
  ':(exclude)dist/*'
  ':(exclude)TranslateGeminiiOS/.DerivedData/*'
  ':(exclude)*.icns'
  ':(exclude)*.png'
  ':(exclude)*.jpg'
  ':(exclude)*.jpeg'
  ':(exclude)*.pdf'
)

status=0

for pattern in "${PATTERNS[@]}"; do
  if git grep -nE "$pattern" -- . "${EXCLUDES[@]}" >/tmp/secret_scan_matches.txt 2>/dev/null; then
    echo "Secret-like value detected for pattern: $pattern"
    cat /tmp/secret_scan_matches.txt
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  echo
  echo "Commit blocked: remove or rotate secrets before commit."
  exit 1
fi

echo "Secret scan passed."
