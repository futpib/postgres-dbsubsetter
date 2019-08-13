#!/usr/bin/env sh

set -xe

export ORIGIN_PORT="${ORIGIN_PORT:-5432}"

: "${ORIGIN_HOST:?ORIGIN_HOST is required}"
: "${ORIGIN_USER:?ORIGIN_USER is required}"
: "${ORIGIN_PASSWORD:?ORIGIN_PASSWORD is required}"
: "${ORIGIN_DB:?ORIGIN_DB is required}"

ORIGIN_PASSWORD_ESCAPED="$(echo "${ORIGIN_PASSWORD}" | sed 's/&/%26/g;s/\$/%24/g')"

POSTGRES_HOST=/var/run/postgresql/
POSTGRES_PORT=5432

POSTGRES_PROXY_PORT=5431

# Pre-Subset Instructions: PostgreSQL
# https://github.com/bluerogue251/DBSubsetter/blob/master/docs/pre_subset_postgres.md

echo "Loading roles..."

# Dump out all postgres roles into a file called `roles.sql`
PGPASSWORD="${ORIGIN_PASSWORD}" \
pg_dumpall \
    --roles-only \
    --no-role-passwords \
    --host="${ORIGIN_HOST}" \
    --port="${ORIGIN_PORT}" \
    --username="${ORIGIN_USER}" \
    --database="${ORIGIN_DB}" \
    | \
    # Load `roles.sql` into your "target" database
    psql \
        --host "${POSTGRES_HOST}" \
        --port "${POSTGRES_PORT}" \
        --user "${POSTGRES_USER}" \
        --dbname "${POSTGRES_DB}"

echo "Loading schema..."

# Dump out just the schema (no data) from your "origin" database into a file called `pre-data-dump.sql`
PGPASSWORD="${ORIGIN_PASSWORD}" \
pg_dump \
    --host "${ORIGIN_HOST}" \
    --port "${ORIGIN_PORT}" \
    --user "${ORIGIN_USER}" \
    --dbname "${ORIGIN_DB}" \
    --section pre-data \
    | \
    # Load `pre-data-dump.sql` into your "target" database
    psql \
        --host "${POSTGRES_HOST}" \
        --port "${POSTGRES_PORT}" \
        --user "${POSTGRES_USER}" \
        --dbname "${POSTGRES_DB}"

echo "Proxying postgres unix socket to tcp..."

socat TCP-LISTEN:"${POSTGRES_PROXY_PORT}" UNIX-CONNECT:"${POSTGRES_HOST}.s.PGSQL.${POSTGRES_PORT}" &
socat_pid=$!

echo "Running dbsubsetter..."

dbsubsetter_script=$(cat <<EOF
java \
    -jar DBSubsetter.jar \
    --originDbConnStr "jdbc:postgresql://${ORIGIN_HOST}:${ORIGIN_PORT}/${ORIGIN_DB}?user=${ORIGIN_USER}&password=${ORIGIN_PASSWORD_ESCAPED}" \
    --targetDbConnStr "jdbc:postgresql://localhost:${POSTGRES_PROXY_PORT}/${POSTGRES_DB}" \
    --originDbParallelism ${DB_SUBSETTER_ORIGIN_PARALLELISM:-1} \
    --targetDbParallelism 1 \
    ${DB_SUBSETTER_ARGS}
EOF
)

eval $dbsubsetter_script

echo "Killing unix to tcp proxy..."

kill $socat_pid

# Post-Subset Instructions: PostgreSQL
# https://github.com/bluerogue251/DBSubsetter/blob/master/docs/post_subset_postgres.md

echo "Loading constraints and indices..."

# Dump out just constraint and index definitions from your "origin" database into a file called `post-data-dump.pg_dump`
PGPASSWORD="${ORIGIN_PASSWORD}" \
pg_dump \
    --host "${ORIGIN_HOST}" \
    --port "${ORIGIN_PORT}" \
    --user "${ORIGIN_USER}" \
    --dbname "${ORIGIN_DB}" \
    --section post-data \
    --format custom \
    | \
    # Load `post-data-dump.pgdump` into your "target" database
    pg_restore \
        --host "${POSTGRES_HOST}" \
        --port "${POSTGRES_PORT}" \
        --user "${POSTGRES_USER}" \
        --dbname "${POSTGRES_DB}"

# Fixing Sequences 
# https://wiki.postgresql.org/wiki/Fixing_Sequences

echo "Fixing sequences..."

create_sequences_script_script=$(cat <<EOF
SELECT 'SELECT SETVAL(' ||
       quote_literal(quote_ident(PGT.schemaname) || '.' || quote_ident(S.relname)) ||
       ', COALESCE(MAX(' ||quote_ident(C.attname)|| '), 1) ) FROM ' ||
       quote_ident(PGT.schemaname)|| '.'||quote_ident(T.relname)|| ';'
FROM pg_class AS S,
     pg_depend AS D,
     pg_class AS T,
     pg_attribute AS C,
     pg_tables AS PGT
WHERE S.relkind = 'S'
    AND S.oid = D.objid
    AND D.refobjid = T.oid
    AND D.refobjid = C.attrelid
    AND D.refobjsubid = C.attnum
    AND T.relname = PGT.tablename
ORDER BY S.relname;
EOF
)

sequences_script=$(
psql \
    --host "${POSTGRES_HOST}" \
    --port "${POSTGRES_PORT}" \
    --user "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --command "${create_sequences_script_script}" \
    | \
    grep 'SELECT'
)

psql \
    --host "${POSTGRES_HOST}" \
    --port "${POSTGRES_PORT}" \
    --user "${POSTGRES_USER}" \
    --dbname "${POSTGRES_DB}" \
    --command "${sequences_script}"
