#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
PRE_COMMIT="$HOOKS_DIR/pre-commit"

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "Not a git repository: $ROOT_DIR"
  exit 1
fi

cat > "$PRE_COMMIT" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
"$(git rev-parse --show-toplevel)/scripts/check_secrets.sh"
HOOK

chmod +x "$PRE_COMMIT"

echo "Installed pre-commit hook: $PRE_COMMIT"
