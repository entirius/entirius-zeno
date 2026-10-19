# enrichment-demo: run it locally

The oohlala test env's setup on Emporium test data: the default storefront, the service with oohlala's module set (no
client code: no `selmo`, no client fixtures) and the CMS release candidate oohlala runs (`v3.3.0-rc.5`). For
working on enrichment and the AI studio.

## 1. The AI toolbox first

Enrichment calls the AI toolbox; with the toolbox enabled it must answer before the seed. Two choices:

- **Local fake toolbox** (default, free, deterministic): clone `entirius/entirius-ai-toolbox` (private GitLab) and
  follow its `docs/deploy-notes.md`, section "Local (port 8300)". It serves the channel `zeno-test` with `fake`
  models only and prints an `ent_test_…` key once.
- **The shared test toolbox**: ask Michał for its URL and a `zeno-test` key (never in a repo or a chat log).

Either way, `.env` of this checkout gets (step 2 creates it):

```bash
AI_TOOLBOX_ENABLED=1
AI_TOOLBOX_BASE_URL=http://host.docker.internal:8300   # or the shared toolbox URL
AI_TOOLBOX_API_KEY=ent_test_…
AI_TOOLBOX_CHANNEL=zeno-test
```

`make toolbox-check` must be green. It goes red on any real (paid) model visible to the channel: a real toolbox
works, but every enrichment run and BDD scenario then costs money.

## 2. The stack

```bash
git clone https://github.com/entirius/entirius-zeno.git && cd entirius-zeno
git checkout feature/enrichment-demo
RECIPE=enrichment-demo make init          # writes RECIPE into the new .env; set AI_TOOLBOX_* now
SETUP_DRY=1 make setup DEV=1 REFS="release/2.3.0 release/3.3.0"   # prints the ref of every clone, changes nothing
make setup DEV=1 REFS="release/2.3.0 release/3.3.0"              # dev mounts, seed (~20-30 min the first time)
```

The REFS matter: the service lock pins `django-enrichment` 2.2.0 and its `develop` is still 2.2.0; the AI studio
needs the 2.3 line, which lives on `release/2.3.0` (tags `v2.3.0rc*`). With this REFS every clean clone that has one
of the listed branches switches to it, the rest go to `develop`, and dev mode installs the clones from `repos/`
over the lock.

`make setup` ends with the URLs and logins (CMS `admin / admin123`); `make urls` prints them again.

## 3. The CMS on v3.3.0-rc.5

In dev mode the CMS runs from `repos/pwa/entirius-pwa-cms` with hot reload; the REFS above put it on
`release/3.3.0`, which is already past rc.5. To work on exactly what oohlala runs:

```bash
git -C repos/pwa/entirius-pwa-cms switch -c fix/<what> v3.3.0-rc.5
make cms-dev
```

The built CMS instead of hot reload: `CMS_BRANCH=v3.3.0-rc.5 make cms` (port 8180).

## Checks

```bash
make recipe-check RECIPE=enrichment-demo MODULES_YAML=repos/services/entirius-service-volkanos/modules.yaml
make health
docker compose logs worker worker-bulk | grep event=    # enrichment runs: plan, consume, reap
make bdd                                                # @needs-toolbox needs the toolbox up
```

What is off compared with `shop`: Magento import/export, BaseLinker, GetResponse, crypt, leads, communicator,
siteintel, regon_api. Their CMS panels are gone and BDD skips their scenarios.
