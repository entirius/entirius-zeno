#!/bin/sh
# cms_patch.sh — film 3 (Price Fighter) changes in the running CMS dev server (lost when the cms container is recreated,
# rerun then).
# CMS_FIX_SRC: checkout of GitHub entirius/entirius-pwa-cms at develop 45397ce2 or later; default ../wt/cms-pf-polish
# next to this clone (worktree of fix/pricefighter-polish on the recording PC). video/README.md, point 6.
# 1. The Price Fighter fix from branch fix/pricefighter-polish (merged into develop in 45397ce2):
#    Gap Table "Produkt" column, reason / strategy / mode in words, history date "Zastosowano", two-decimal preview.
#    The PriceFighter views are identical in v3.7.0 and develop, so they are copied as they are; the locales differ,
#    so only the fix's pricefighter keys are added.
# 2. Video only: no raw channel id ("sloik-pl") under the market (the product keeps it on purpose).
set -eu
C=entirius-zeno-video-cms-1
APP=/entirius/pwa/entirius-pwa-cms
SRC=${CMS_FIX_SRC:-$(cd "$(dirname "$0")/../.." && pwd)/wt/cms-pf-polish}
[ -d "$SRC/src/views/PriceFighter" ] || {
  echo "no entirius-pwa-cms checkout at $SRC: set CMS_FIX_SRC (develop 45397ce2 or later, video/README.md)" >&2; exit 1; }
for f in GapTable.vue Strategies.vue DecisionHistory.vue constants.js \
         components/GapRowDetail.vue components/ApplyPreviewModal.vue components/MarketCell.vue; do
  docker cp "$SRC/src/views/PriceFighter/$f" "$C:$APP/src/views/PriceFighter/$f"
done
tmp=$(mktemp -d)
for lang in en pl; do
  docker cp "$C:$APP/src/i18n/locales/$lang.json" "$tmp/$lang.json"
  python3 - "$tmp/$lang.json" "$SRC/src/i18n/locales/$lang.json" <<'EOF'
import json, sys
target, source = sys.argv[1], sys.argv[2]
data = json.load(open(target))
fix = json.load(open(source))["pricefighter"]
keys = [k for k in fix if k.startswith(("reason_", "mode_")) or k in ("product", "applied_at")]
data["pricefighter"].update({k: fix[k] for k in keys})
json.dump(data, open(target, "w"), ensure_ascii=False, indent=2)
open(target, "a").write("\n")
EOF
  docker cp "$tmp/$lang.json" "$C:$APP/src/i18n/locales/$lang.json"
done
rm -rf "$tmp"
docker exec "$C" sed -i \
  's#<span class="market-cell__channel t-muted fs-200">{{ channel }}</span>#<span v-if="false" class="market-cell__channel t-muted fs-200">{{ channel }}</span>#' \
  "$APP/src/views/PriceFighter/components/MarketCell.vue"
echo "CMS patched (Price Fighter fix + hidden channel id); reload the page"
