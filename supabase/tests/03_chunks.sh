#!/usr/bin/env bash
# Loads the chunked import files in order (as you would in the Supabase SQL editor).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; DIR="$(realpath "$1")"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"; DATA="$(mktemp -d)"; PORT=55434
trap '"$PGBIN/pg_ctl" -D "$DATA" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DATA"' EXIT
if [ "$(id -u)" = "0" ]; then RUNAS=(su postgres -s /bin/bash -c); chown postgres "$DATA"; else RUNAS=(bash -c); fi
"${RUNAS[@]}" "$PGBIN/initdb -D $DATA -U postgres -A trust >/dev/null"
"${RUNAS[@]}" "$PGBIN/pg_ctl -D $DATA -o '-p $PORT -k /tmp' -l $DATA/log start >/dev/null"; sleep 1
P=(psql -h /tmp -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -d postgres)
"${P[@]}" -f "$HERE/00_auth_shim.sql"; "${P[@]}" -f "$HERE/../migrations/0001_init.sql"
for f in "$DIR"/*.sql; do "${P[@]}" -f "$f"; done
"${P[@]}" -At -c "select 'chunks ok: ayahs='||(select count(*) from quran.ayahs)||' words='||(select count(*) from quran.words)||' bismillah='||(select count(bismillah_text) from quran.surahs)"
