#!/bin/sh
# pf_fresh.sh — moves the film-2 competitor observations to "a few hours ago" again (Price Fighter flags
# observations older than 3 days as stale). Run after `state.sh restore C|D` on a later day.
set -eu
docker exec entirius-zeno-video-db-1 psql -U entirius -d entirius -qc "
UPDATE django_atlas_observation o SET ts = now() - (interval '1 hour' * (1 + (o.id % 6)))
FROM django_atlas_source s WHERE s.id = o.source_id
AND s.idx IN ('chwilownia.pl', 'sloikowo.pl', 'zamknietewszkle.pl');"
echo "observations moved to 1-6 hours ago"
