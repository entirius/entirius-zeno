#!/usr/bin/env bash
# The canonical .gitleaks.toml must be linked in zeno AND in every mounted clone that gitignores it.
# A clone scanned without it gets default rules only, so a client name can reach a public repo unnoticed —
# exactly how one slipped into the CMS on 2026-08-24. Clones that do not gitignore the symlink are skipped:
# linking there would dirty the operator's tree.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
grep -q forbidden-names .gitleaks.toml 2>/dev/null || {
  echo "Missing or non-canonical .gitleaks.toml — symlink the config per the internal secret-scanning standard"
  exit 1
}
missing=()
for d in repos/*/*/; do
  [[ -d $d.git ]] || continue
  grep -qx '\.gitleaks\.toml' "$d.gitignore" 2>/dev/null || continue
  grep -q forbidden-names "$d.gitleaks.toml" 2>/dev/null || missing+=("$d")
done
(( ${#missing[@]} == 0 )) || {
  printf 'clones without the canonical .gitleaks.toml:\n'
  printf '  %s\n' "${missing[@]}"
  printf '  fix: ln -s "%s" <clone>/.gitleaks.toml\n' "$(readlink .gitleaks.toml)"
  exit 1
}
