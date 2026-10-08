#!/bin/bash
# Local test runner (Postgres 16 on /tmp/pg:5433). Usage: ./run_local.sh [dbname]
DB=${1:-sc}; D=$(dirname "$0")
P="psql -h ${PGHOST:-/tmp/pg} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q -At"
psql -h ${PGHOST:-/tmp/pg} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -q -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB" 2>/dev/null
$P -d $DB -f $D/supabase_stub.sql >/dev/null
# every dated migration, in order (2026_10_audit_fixes.sql first)
for M in $(ls $D/../20[0-9][0-9]_*.sql | sort); do
  $P -d $DB -f $M >/dev/null 2>&1 || { echo "MIGRATION FAILED: $(basename $M)"; $P -d $DB -f $M 2>&1 | grep -m3 ERROR; exit 1; }
done
OUT=$( (cd $D && $P -d $DB -f scenario_test.sql) 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED|LINE|CONTEXT" | sed 's/^psql:[^:]*:[0-9]*: //; s/NOTICE:  //')
echo "$OUT"
echo "$OUT" | grep -q "ALL SCENARIO TESTS PASSED" || exit 1
