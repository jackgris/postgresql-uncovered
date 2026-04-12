#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="pgtrace"
IMAGE="centos:7"
CONTAINER_TRACE_FILE="/home/pguser/trace.log"
HOST_TRACE_FILE="$ROOT_DIR/trace.log"
PG_BIN_DIR="/work/pgsql/bin"
PG_LIB_DIR="/work/pgsql/lib"
PGDATA_DIR="/work/pgdata"

docker_exec_pguser() {
  docker exec -it "$CONTAINER_NAME" /bin/bash -lc \
    "su - pguser -c 'LD_LIBRARY_PATH=$PG_LIB_DIR $*'"
}

docker_exec_pguser_noninteractive() {
  docker exec "$CONTAINER_NAME" /bin/bash -lc \
    "su - pguser -c 'LD_LIBRARY_PATH=$PG_LIB_DIR $*'"
}

ensure_container_running() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    printf 'Container %s is not running. Start it first with: %s start\n' "$CONTAINER_NAME" "$0" >&2
    exit 1
  fi
}

start_container() {
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    printf 'Container %s is already running.\n' "$CONTAINER_NAME"
    return 0
  fi

  docker run --rm -d \
    --name "$CONTAINER_NAME" \
    -p 5432:5432 \
    -v "$ROOT_DIR:/work" \
    -w /work \
    "$IMAGE" \
    /bin/bash -lc "getent group $(id -g) >/dev/null || groupadd -g $(id -g) pggrp; id -u pguser >/dev/null 2>&1 || useradd -m -u $(id -u) -g $(id -g) pguser; su - pguser -c 'LD_LIBRARY_PATH=$PG_LIB_DIR $PG_BIN_DIR/postgres -D $PGDATA_DIR -k /tmp'"

  printf 'Started %s.\n' "$CONTAINER_NAME"
}

usage() {
  cat <<'EOF'
Usage: ./trace.sh <command> [args]

Commands:
  help                  Show this help message
  init                  Initialize ./pgdata if it does not exist yet
  start                 Start the PostgreSQL trace container
  restart               Stop container, recreate pgdata, and start fresh
  stop                  Stop the PostgreSQL trace container
  status                Show container status
  psql                  Open interactive psql inside the container
  run "SQL"             Run one SQL statement non-interactively
  runfile <file.sql>    Run SQL from a file on the host
  clear                 Clear the trace log inside the container
  fetch                 Copy the container trace log to ./trace.log
  tail                  Show the last 40 lines of the container trace log
  logs                  Show container logs

Notes:
  - The live trace is written inside the container at /home/pguser/trace.log.
  - The fetch command copies that file to ./trace.log on your host.
  - Run init once before start if ./pgdata has not been created yet.

Examples:
  ./trace.sh init
  ./trace.sh start
  ./trace.sh clear
  ./trace.sh run "select version();"
  ./trace.sh runfile ./example.sql
  ./trace.sh fetch
  less ./trace.log
EOF
}

recreate_pgdata() {
  rm -rf "$ROOT_DIR/pgdata"
  mkdir -p "$ROOT_DIR/pgdata"

  docker run --rm -it \
    -v "$ROOT_DIR:/work" \
    -w /work \
    "$IMAGE" \
    /bin/bash -lc "getent group $(id -g) >/dev/null || groupadd -g $(id -g) pggrp; id -u pguser >/dev/null 2>&1 || useradd -m -u $(id -u) -g $(id -g) pguser; su - pguser -c 'LD_LIBRARY_PATH=$PG_LIB_DIR $PG_BIN_DIR/initdb -D $PGDATA_DIR'"
}

cmd="${1:-}"

case "$cmd" in
  help)
    usage
    ;;
  init)
    if [ -f "$ROOT_DIR/pgdata/PG_VERSION" ]; then
      printf 'pgdata is already initialized at %s/pgdata\n' "$ROOT_DIR"
      exit 0
    fi
    recreate_pgdata
    ;;
  start)
    start_container
    ;;
  restart)
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
      docker stop "$CONTAINER_NAME" >/dev/null || true
    fi
    rm -f "$HOST_TRACE_FILE"
    recreate_pgdata
    start_container
    ;;
  stop)
    docker stop "$CONTAINER_NAME"
    ;;
  status)
    docker ps -a --filter "name=$CONTAINER_NAME"
    ;;
  psql)
    ensure_container_running
    docker_exec_pguser "$PG_BIN_DIR/psql -h 127.0.0.1 -p 5432 -d postgres"
    ;;
  run)
    ensure_container_running
    sql="${2:-}"
    if [ -z "$sql" ]; then
      printf 'Provide SQL as the second argument.\n' >&2
      exit 1
    fi
    docker_exec_pguser_noninteractive "$PG_BIN_DIR/psql -h 127.0.0.1 -p 5432 -d postgres -c \"$sql\""
    ;;
  runfile)
    ensure_container_running
    sql_file="${2:-}"
    if [ -z "$sql_file" ]; then
      printf 'Provide a SQL file as the second argument.\n' >&2
      exit 1
    fi
    if [ ! -f "$sql_file" ]; then
      printf 'SQL file not found: %s\n' "$sql_file" >&2
      exit 1
    fi
    abs_file="$(realpath "$sql_file")"
    case "$abs_file" in
      "$ROOT_DIR"/*)
        container_sql_file="/work/${abs_file#$ROOT_DIR/}"
        docker_exec_pguser_noninteractive "$PG_BIN_DIR/psql -h 127.0.0.1 -p 5432 -d postgres -f $container_sql_file"
        ;;
      *)
        printf 'SQL file must be inside %s so the container can access it.\n' "$ROOT_DIR" >&2
        exit 1
        ;;
    esac
    ;;
  clear)
    ensure_container_running
    docker exec "$CONTAINER_NAME" /bin/bash -lc "su - pguser -c ': > $CONTAINER_TRACE_FILE'"
    printf 'Cleared %s\n' "$CONTAINER_TRACE_FILE"
    ;;
  fetch)
    ensure_container_running
    docker cp "$CONTAINER_NAME:$CONTAINER_TRACE_FILE" "$HOST_TRACE_FILE"
    printf 'Copied trace to %s\n' "$HOST_TRACE_FILE"
    ;;
  tail)
    ensure_container_running
    docker exec -it "$CONTAINER_NAME" /bin/bash -lc "su - pguser -c 'tail -n 40 $CONTAINER_TRACE_FILE'"
    ;;
  logs)
    docker logs "$CONTAINER_NAME"
    ;;
  *)
    usage
    exit 1
    ;;
esac
