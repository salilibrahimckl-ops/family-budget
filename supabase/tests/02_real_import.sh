#!/usr/bin/env bash
# Loads the real Tanzil import into a throwaway Postgres and checks it against the schema.
# Usage: ./02_real_import.sh path/to/quran_import.sql
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SQL="$(realpath "$1")"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"; DATA="$(mktemp -d)"; PORT=55433
trap '"$PGBIN/pg_ctl" -D "$DATA" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DATA"' EXIT
if [ "$(id -u)" = "0" ]; then RUNAS=(su postgres -s /bin/bash -c); chown postgres "$DATA"; else RUNAS=(bash -c); fi
"${RUNAS[@]}" "$PGBIN/initdb -D $DATA -U postgres -A trust >/dev/null"
"${RUNAS[@]}" "$PGBIN/pg_ctl -D $DATA -o '-p $PORT -k /tmp' -l $DATA/log start >/dev/null"; sleep 1
P=(psql -h /tmp -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q -d postgres)
"${P[@]}" -f "$HERE/00_auth_shim.sql"; "${P[@]}" -f "$HERE/../migrations/0001_init.sql"; "${P[@]}" -f "$SQL"
"${P[@]}" -At -c "select 'ayahs='||count(*)||' surahs='||(select count(*) from quran.surahs)||' bismillah='||(select count(*) from quran.surahs where bismillah_text is not null)||' juz30_start='||(select surah_id||':'||ayah_number from quran.ayahs where juz=30 order by id limit 1)||' per_surah_ok='||(select bool_and(s.ayah_count=(select count(*) from quran.ayahs a where a.surah_id=s.id)) from quran.surahs s) from quran.ayahs"
out=$("${P[@]}" -c "update quran.ayahs set text_uthmani = text_uthmani where id = 1" 2>&1 || true); echo "$out" | grep -q immutable && echo "immutability holds on real data"
