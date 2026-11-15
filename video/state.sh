#!/bin/sh
# state.sh save|restore <name> — snapshot / restore the video stack's database and media volume (entirius-zeno-video).
# restore stops service, workers and beat, replaces the database and the media files, clears Redis, starts them again.
set -eu
cd "$(dirname "$0")/.."
action=${1:?usage: state.sh save|restore <name>}; name=${2:?usage: state.sh save|restore <name>}
P=entirius-zeno-video; DB=$P-db-1; APPS="$P-service-1 $P-worker-1 $P-worker-bulk-1 $P-beat-1"
dump=video/state-$name.dump; media=video/state-$name-media.tar
case "$action" in
  save)
    docker exec "$DB" pg_dump -U entirius -Fc entirius > "$dump"
    docker run --rm -v ${P}_media:/m:ro alpine tar -C /m -cf - . > "$media"
    echo "saved $dump ($(du -h "$dump" | cut -f1)) and $media ($(du -h "$media" | cut -f1))" ;;
  restore)
    test -s "$dump" || { echo "no $dump"; exit 1; }
    docker stop $APPS >/dev/null
    docker exec "$DB" psql -U entirius -d postgres -qc "DROP DATABASE IF EXISTS entirius WITH (FORCE)" -c "CREATE DATABASE entirius OWNER entirius"
    docker exec -i "$DB" pg_restore -U entirius -d entirius --no-owner < "$dump"
    docker run --rm -i -v ${P}_media:/m alpine sh -c 'find /m -mindepth 1 -delete; tar -C /m -xf -' < "$media"
    docker exec $P-redis-1 redis-cli FLUSHALL >/dev/null
    docker start $APPS >/dev/null
    port=$(grep '^SERVICE_PORT=' .env | cut -d= -f2)
    for i in $(seq 60); do [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://localhost:$port/api/token/)" = 405 ] && break; sleep 2; done
    echo "restored state $name; API http://localhost:$port" ;;
  *) echo "usage: state.sh save|restore <name>"; exit 1 ;;
esac
