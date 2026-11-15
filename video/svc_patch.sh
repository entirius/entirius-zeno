#!/bin/sh
# svc_patch.sh — local fix in the baked service image (lost when the containers are recreated, rerun then):
# django_pricemanager.services.price_output_service.get_current_prices returned bundle-component rows
# (product_parent set) next to the product's own price, so the storefront read model showed whichever row came
# last: a Price Fighter change of a product that sits in a bundle never reached the product page.
set -eu
F=/entirius/services/entirius-service-volkanos/.venv/lib/python3.12/site-packages/django_pricemanager/services/price_output_service.py
PY=/entirius/services/entirius-service-volkanos/.venv/bin/python
for c in entirius-zeno-video-service-1 entirius-zeno-video-worker-1 entirius-zeno-video-worker-bulk-1 entirius-zeno-video-beat-1; do
  docker exec -i "$c" "$PY" - "$F" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
if "# video patch" in s:
    sys.exit(0)
old = '        country__iso2=country,\n    ).select_related("product", "tax_rate", "product_parent", "customer_representation")'
new = ('        country__iso2=country,\n        product_parent__isnull=True,  # video patch\n'
       '    ).select_related("product", "tax_rate", "product_parent", "customer_representation")')
if s.count(old) < 1:
    sys.exit("pattern not found in " + p)
open(p, "w").write(s.replace(old, new, 1))
EOF
done
docker restart entirius-zeno-video-worker-1 entirius-zeno-video-worker-bulk-1 entirius-zeno-video-beat-1 >/dev/null
echo "pricemanager patched in service, workers and beat; workers restarted"
