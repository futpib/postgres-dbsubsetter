#!/usr/bin/env sh

export ORIGIN_PORT="${ORIGIN_PORT:-5432}"

: "${ORIGIN_HOST:?ORIGIN_HOST is required}"
: "${ORIGIN_USER:?ORIGIN_USER is required}"
: "${ORIGIN_PASSWORD:?ORIGIN_PASSWORD is required}"
: "${ORIGIN_DB:?ORIGIN_DB is required}"

ORIGIN_PASSWORD_ESCAPED="$(echo "${ORIGIN_PASSWORD}" | sed 's/&/%26/g;s/\$/%24/g')"

POSTGRES_HOST=/var/run/postgresql/
POSTGRES_PORT=5432

POSTGRES_PROXY_PORT=5431

echo "Loading roles..."

PGPASSWORD="${ORIGIN_PASSWORD}" \
pg_dumpall \
    --roles-only \
    --host="${ORIGIN_HOST}" \
    --port="${ORIGIN_PORT}" \
    --username="${ORIGIN_USER}" \
    --database="${ORIGIN_DB}" \
    | \
    psql \
        --host "${POSTGRES_HOST}" \
        --port "${POSTGRES_PORT}" \
        --user "${POSTGRES_USER}" \
        --dbname "${POSTGRES_DB}"

echo "Loading schema..."

PGPASSWORD="${ORIGIN_PASSWORD}" \
pg_dump \
    --host "${ORIGIN_HOST}" \
    --port "${ORIGIN_PORT}" \
    --user "${ORIGIN_USER}" \
    --dbname "${ORIGIN_DB}" \
    --section pre-data \
    | \
    psql \
        --host "${POSTGRES_HOST}" \
        --port "${POSTGRES_PORT}" \
        --user "${POSTGRES_USER}" \
        --dbname "${POSTGRES_DB}"

echo "Proxying postgres unix socket to tcp..."

socat TCP-LISTEN:"${POSTGRES_PROXY_PORT}" UNIX-CONNECT:"${POSTGRES_HOST}.s.PGSQL.${POSTGRES_PORT}" &
SOCAT_PID=$!

echo "Running dbsubsetter..."

SCRIPT=$(cat <<EOF
java \
    -jar DBSubsetter.jar \
    --originDbConnStr "jdbc:postgresql://${ORIGIN_HOST}:${ORIGIN_PORT}/${ORIGIN_DB}?user=${ORIGIN_USER}&password=${ORIGIN_PASSWORD_ESCAPED}" \
    --targetDbConnStr "jdbc:postgresql://localhost:${POSTGRES_PROXY_PORT}/${POSTGRES_DB}" \
    --originDbParallelism 1 \
    --targetDbParallelism 1 \
    ${DB_SUBSETTER_ARGS}
EOF
)

eval $SCRIPT

echo "Killing unix to tcp proxy..."

kill $SOCAT_PID
