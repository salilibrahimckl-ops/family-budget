#!/usr/bin/env bash
# Spins up a throwaway Postgres 16, applies the migration, runs the tests.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
DATA="$(mktemp -d)"
PORT="${PORT:-55432}"
trap '"$PGBIN/pg_ctl" -D "$DATA" stop -m fast >/dev/null 2>&1 || true; rm -rf "$DATA"' EXIT

if [ "$(id -u)" = "0" ]; then RUNAS=(su postgres -s /bin/bash -c); chown postgres "$DATA"; else RUNAS=(bash -c); fi
"${RUNAS[@]}" "$PGBIN/pg_ctl -D /dev/null status" >/dev/null 2>&1 || true
for p in $(pgrep -f "postgres.*-p $PORT"); do kill "$p" 2>/dev/null || true; done; sleep 1
"${RUNAS[@]}" "$PGBIN/initdb -D $DATA -U postgres -A trust >/dev/null"
"${RUNAS[@]}" "$PGBIN/pg_ctl -D $DATA -o '-p $PORT -k /tmp' -l $DATA/log start >/dev/null"
sleep 1
PSQL=(psql -h /tmp -p "$PORT" -U postgres -v ON_ERROR_STOP=1 -q)
"${PSQL[@]}" -c "create database hifz_test"
"${PSQL[@]}" -d hifz_test -f "$HERE/00_auth_shim.sql"
"${PSQL[@]}" -d hifz_test -f "$HERE/../migrations/0001_init.sql"
"${PSQL[@]}" -d hifz_test -f "$HERE/01_schema_tests.sql" 2>&1 | sed 's/^psql:[^:]*:[0-9]*: //'
