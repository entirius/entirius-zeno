"""Price Fighter data for film 2 (Słoik Chwil, channel sloik-pl, market PL/PLN). Idempotent; run in the service container:
docker exec -i entirius-zeno-video-service-1 sh -c 'cd /entirius/services/entirius-service-volkanos && .venv/bin/python manage.py shell' < video/pf_seed.py

Prices are gross PLN. Baseline = net cost * 1.20 * 1.23 (a cost of P / 1.476 puts it at the current price P);
floor = net cost * 1.05 * 1.23. Compete sets our price to the cheapest competitor (undercut 0), raise to it minus 1 PLN.
"""
from datetime import timedelta
from decimal import Decimal as D

from django.core.management import call_command
from django.utils import timezone
from django_atlas.enums import ReviewMode, SourceKind, SourceType
from django_atlas.models import Observation, Source
from django_atlas.services.observation_service import record_observation
from django_pricefighter.models import Channel as PfChannel, PricingRule, QuoteConfig
from django_pricemanager.models import BaselineConfig, PriceBoundsConfig, PurchaseCost
from django_pricemanager.models import Channel as PmChannel, ProductRepresentation as PmRep
from django_regional.models import Country, Currency, Language

CH, CUR = "sloik-pl", "PLN"
pl, pln = Country.objects.get(iso2__iexact="PL"), Currency.objects.get(iso3=CUR)
SOURCES = {"chwilownia.pl": "chwilownia.pl", "sloikowo.pl": "sloikowo.pl", "zamknietewszkle.pl": "zamknietewszkle.pl"}
OLD_SOURCES = ["chwilownia-pl", "sloikowo-pl", "zamknietewszkle-pl", "pf-pracownia", "pf-kredens", "pf-okazje", "pracownia-wspomnien", "szklany-kredens", "okazje-tu-i-teraz"]
C, S, Z = SOURCES  # source idxs
# sku: (net cost, [(source, observed gross price, hours ago)])
CASES = {
    "SC-WIO-002": ("23.71", [(C, "31.99", 2), (S, "33.49", 5)]),   # hero, 34.99: compete -> 31.99
    "SC-WIO-004": ("25.06", [(S, "33.99", 3), (Z, "35.49", 1)]),   # 36.99: compete -> 33.99
    "SC-WIO-006": ("27.09", [(Z, "36.99", 4)]),                    # 39.99: compete -> 36.99
    "SC-WIO-007": ("29.13", [(C, "39.99", 6), (Z, "41.49", 2)]),   # 42.99: compete -> 39.99
    "SC-WIO-001": ("30.48", [(S, "36.99", 3)]),                    # 44.99: price war -> hold at floor 39.36
    "SC-WIO-009": ("28.45", [(C, "34.99", 5)]),                    # 41.99: price war -> hold at floor 36.74
    "SC-WIO-003": ("22.35", [(Z, "32.49", 2)]),                    # 32.99: hold, in band
    "SC-LAT-004": ("30.48", [(C, "52.99", 1), (S, "54.99", 4)]),   # 44.99: raise -> 51.99
    "SC-LAT-005": ("25.06", [(Z, "44.99", 3)]),                    # 36.99: raise -> 43.99
    "SC-LAT-006": ("24.38", [(S, "36.49", 2)]),                    # 35.99: hold, in band
    "SC-LAT-009": ("29.13", [(C, "42.49", 6)]),                    # 42.99: hold, in band
}
PRICE_WAR = ["SC-WIO-001", "SC-WIO-009"]


def sources():
    Source.objects.filter(idx__in=OLD_SOURCES).delete()
    for idx, name in SOURCES.items():
        Source.objects.update_or_create(idx=idx, defaults={
            "kind": SourceKind.MONITORING, "source_type": SourceType.FEED, "review_mode": ReviewMode.MANUAL,
            "is_active": True, "is_trusted": True, "default_language": Language.objects.get(iso2="pl"),
            "default_currency": pln, "qty_subtract": 0, "qty_minimum": 0, "realproduct_match_tolerance_pct": 10,
            "disable_ean_auto_link": False, "name": name, "sku_prefix": idx.upper().replace("-", "")[:8],
            "country": pl})


def configs():
    pm = PmChannel.objects.get(idx=CH)
    BaselineConfig.objects.update_or_create(channel=pm, defaults={"markup_percent": D("0.20")})
    g = PriceBoundsConfig.objects.filter(product__isnull=True, channel__isnull=True).first()
    if g:
        g.min_margin_percent, g.map_value = D("0.05"), None
        g.save()
    else:
        PriceBoundsConfig.objects.create(product=None, channel=None, min_margin_percent=D("0.05"))
    cfg, _ = QuoteConfig.objects.update_or_create(currency=CUR, range_from=D("0"), range_to=None, defaults={
        "band_dn": D("1.50"), "band_up": D("1.50"), "undercut": D("0.00"), "headroom": D("1.00"),
        "max_step": D("10.00"), "rounding": "none"})
    cfg.full_clean()
    PurchaseCost.objects.filter(channel=pm).exclude(product__sku__in=list(CASES)).delete()
    for sku, (cost, _) in CASES.items():
        PurchaseCost.objects.update_or_create(product=PmRep.objects.get(sku=sku), channel=pm,
            defaults={"country": pl, "currency": pln, "net_cost": D(cost)})


def rules():
    PricingRule.objects.all().delete()
    PricingRule.objects.create(channel=PfChannel.objects.get(idx=CH), strategy="compete", mode="suggestion")
    PricingRule.objects.create(category_idx="lato", strategy="raise", mode="suggestion")
    for sku in PRICE_WAR:
        PricingRule.objects.create(sku=sku, strategy="compete", mode="suggestion", price_war=True)


def observations():
    Observation.objects.filter(source__idx__in=list(SOURCES)).delete()
    now = timezone.now()
    for sku, (_, obs) in CASES.items():
        for idx, price, hours in obs:
            record_observation(source=Source.objects.get(idx=idx), sku=sku,
                value={"price": price, "currency": CUR, "stock": 5})
            Observation.objects.filter(source__idx=idx, sku=sku).update(ts=now - timedelta(hours=hours))


call_command("sync_pricefighter_channels")
call_command("pricefighter_full_sync")
sources(); configs(); rules(); observations()

from django_pricefighter.services import decision_view_service  # noqa: E402

rows, total = decision_view_service.build_decision_rows(skus=list(CASES))
for r in rows:
    d = r.decision
    if d.channel_idx == CH and d.country == "PL":
        print(f"{d.sku} P={d.current_price} B={d.baseline} F={d.floor} R={d.reference_price} "
              f"-> {d.recommendation} {d.suggested_price} ({d.reason})")
