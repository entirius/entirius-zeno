# Video stack (product films 1, 3 and 5)

An isolated zeno stack, docker project `entirius-zeno-video`, ports +4000, for recording the product films in
`content-workbench/research/video/third-pass/` (`01-jakosc-danych`, `03-price-fighter`, `05-poprawka-i-wdrozenie`).
Not for BDD or e2e: the AI toolbox is the test deployment with real models.

- CMS http://localhost:12180 (admin / admin123, dev only; Polish UI: `localStorage.setItem('cms_lang','PL')`, reload)
- Storefront http://localhost:7100, API http://localhost:12100
- Service v4.3.0 (pim 3.6.1, enrichment 2.3.0), CMS v3.7.0, package Słoik Chwil (`demo` layer), channel `sloik-pl`

## What this branch changes against develop

- `media` volume for `MEDIA_ROOT` in service, workers and beat (an AI image task reads what `service` imported).
- `TEST_PACKAGE` picks the package mounted at `/entirius/test-package` (default stays Emporium).
- `docker/Dockerfile.pwa`: storefront languages, currencies and menu (`menu_url_keys`) as build args, defaults for Słoik.
- `recipes/shop/apps.txt` without `django_todo` and `django_stock_alerts`: service v4.3.0 has neither.

## 1. Clone

Use a separate checkout, so the main zeno clone keeps its own stack and branch:

```bash
git clone -b content-workbench <zeno remote or ~/kloczi_pc/coding/entirius/entirius-zeno> entirius-zeno-video
cd entirius-zeno-video
git clone -b feature/sloik-chwil https://github.com/entirius/entirius-test-package-1.git repos/tests/entirius-test-package-1
```

## 2. `.env`

`cp .env.example .env`, then change these (everything else as in the example):

```
COMPOSE_PROJECT_NAME=entirius-zeno-video     # the video/*.sh scripts expect this name
SERVICE_BRANCH=v4.3.0
CMS_BRANCH=v3.7.0
TEST_PACKAGE=entirius-test-package-1
PWA_CHANNEL=sloik-pl
SERVICE_PORT=12100  POSTGRES_PORT=9532  REDIS_PORT=10479  RABBITMQ_PORT=9772  RABBITMQ_MANAGEMENT_PORT=19772
PWA_PORT=7100  CMS_PORT=12180  DASHBOARD_PORT=12200  DOCS_PORT=8421  DOCS_ALT_PORT=8422  WWW_PORT=7200  EMBED_PORT=12097
GREENMAIL_SMTP_PORT=7125  GREENMAIL_IMAP_PORT=7243  GREENMAIL_API_PORT=12380  MAILPIT_UI_PORT=12125  MAILPIT_SMTP_PORT=5125
AI_TOOLBOX_ENABLED=1  AI_TOOLBOX_BASE_URL=<test toolbox>  AI_TOOLBOX_API_KEY=<test toolbox key>  AI_TOOLBOX_CHANNEL=<its channel>
```

The toolbox key comes from the test toolbox owner; it never goes into git. `make toolbox-check` verifies it.

## 3. Start and stop

```bash
make build                                  # first time: service image at SERVICE_BRANCH
make up && make mail && make cms && make pwa
make down                                   # stop; keeps the volumes (the stack takes about 6-7 GB RAM)
```

## 4. Seed

From scratch (empty database), the Słoik package's `demo` layer:

```bash
make seed TESTS_REPO=entirius-test-package-1 PACKAGE_LAYERS=demo   # about 11 min
```

The last step (seed check) can end with `queues not drained after 600s` while the data is loaded; the shop and CMS work.
The film-1 setup on top of the seed (five rules with Polish names, `gaps_enabled`, PIM -> shop sync, the AI task)
was done by hand in the CMS and exists only in the state dumps A and B. `video/pf_seed.py` builds the film-3 Price Fighter
data (sources, costs, rules, observations) on any state, idempotent:

```bash
docker exec -i entirius-zeno-video-service-1 sh -c \
  'cd /entirius/services/entirius-service-volkanos && .venv/bin/python manage.py shell' < video/pf_seed.py
```

## 5. States: save, restore, fresh

```bash
video/state.sh save <name>      # video/state-<name>.dump (database) + state-<name>-media.tar (media volume)
video/state.sh restore <name>   # stops service/workers/beat, replaces db and media, flushes Redis, starts them again
video/pf_fresh.sh               # after restore C|D: competitor observations to 1-6 h ago (older than 3 days = stale)
```

The dumps (about 80 MB each) are not in git (`video/.gitignore`): copy `video/state-*` from the recording PC
(`~/kloczi_pc/coding/entirius/entirius-zeno-video/video/`). Without them: seed, redo the film-1 setup, `pf_seed.py`, `save`.

| State | Contents | Film |
|---|---|---|
| A | gaps detected, no proposals; hero `SC-WIO-002` with empty meta, short description, one picture | 1: sklep-przed, lista, zlecenie |
| B | 10 AI proposals pending | 1: propozycje, lista-po, sklep-po |
| C | Price Fighter "before": 11 rows on sloik-pl, empty history | 3: all clips (applying the prices in the clip makes "after") |
| D | Price Fighter "after": 4 prices applied through the UI, 4 history entries | 3: re-record historia / sklep-po alone |

Film 5 needs no state: it swaps one CMS file in the running container (`05-*/flows/wersja.sh przed|po`) and edits the
page "Jak dbać o słoik", which every state has. Re-recording film 1 restores A and B itself (`01-*/flows/rerecord.sh all`).

## 6. Container patches

Lost when the containers are recreated (`make up` after a build, `make cms`); rerun then:

- `video/svc_patch.sh`: pricemanager in the baked v4.3.0 image, bundle-component price rows no longer reach the
  product page (film 3: the hero sits in a bundle). Same fix as entirius-django-pricemanager 763e203 on develop.
- `video/cms_patch.sh`: Price Fighter Gap Table "Produkt" column, reasons and modes in words, history date
  "Zastosowano", two-decimal preview, no raw `sloik-pl` under the market. Copies the views from a CMS checkout:
  `CMS_FIX_SRC=<entirius-pwa-cms at develop, 45397ce2 or later>` (default `../wt/cms-pf-polish`).

Both become unnecessary once the stack runs a service and CMS release that contains these commits.
