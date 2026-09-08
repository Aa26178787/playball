#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MIGRATION_DIR=$(cd "$SCRIPT_DIR/../database/migrations" && pwd)
DB_NAME=${DB_NAME:-playball}

psql_db() {
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$DB_NAME" "$@"
}

psql_db <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    filename TEXT PRIMARY KEY,
    sha256 TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
SQL

if [ "$#" -gt 0 ]; then
    files=("$@")
else
    mapfile -t files < <(find "$MIGRATION_DIR" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)
fi

for name in "${files[@]}"; do
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+\.sql$ ]]; then
        echo "invalid migration name: $name" >&2
        exit 2
    fi
    file="$MIGRATION_DIR/$name"
    if [ ! -f "$file" ]; then
        echo "migration not found: $file" >&2
        exit 2
    fi

    checksum=$(sha256sum "$file" | awk '{print $1}')
    applied=$(psql_db -Atc "SELECT sha256 FROM schema_migrations WHERE filename = '$name'")
    if [ -n "$applied" ]; then
        if [ "$applied" != "$checksum" ]; then
            echo "migration checksum mismatch: $name" >&2
            exit 3
        fi
        echo "skip $name"
        continue
    fi

    echo "apply $name"
    psql_db <<SQL
BEGIN;
\i '$file'
INSERT INTO schema_migrations(filename, sha256) VALUES ('$name', '$checksum');
COMMIT;
SQL
done
