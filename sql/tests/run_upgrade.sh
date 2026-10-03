#!/bin/bash
# Build a DB from the 47 historical files, seed old-app data, migrate, test.
D=$(cd $(dirname "$0") && pwd)
P="psql -h ${PGHOST:-/tmp/pg} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q -At"
$D/build_legacy.sh up >/dev/null
$P -d up -f $D/legacy_seed.sql >/dev/null || exit 1
$P -d up -f $D/../2026_10_audit_fixes.sql >/dev/null 2>&1 || { echo "MIGRATION FAILED"; $P -d up -f $D/../2026_10_audit_fixes.sql 2>&1 | grep -m3 ERROR; exit 1; }
OUT=$( (cd $D && $P -d up -f upgrade_test.sql 2>&1 | grep -E "ok  |FAIL|ERROR|PASSED|CONTEXT" | sed 's/^psql:[^:]*:[0-9]*: //; s/NOTICE:  //'))
echo "$OUT"
echo "$OUT" | grep -q "ALL UPGRADE TESTS PASSED" || exit 1
