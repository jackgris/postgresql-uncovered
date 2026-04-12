# PostgreSQL Trace Helper

This repository is a small helper environment for the course [`PostgreSQL Uncovered: Internals, Trace Analysis, and Performance`](https://wangbin579.gumroad.com/l/postgresql_course).

The course includes a custom PostgreSQL 17.2 trace-enabled build for `el7` systems. Running that build directly on a modern Linux distribution can be inconvenient because of older runtime dependencies. The `trace.sh` script wraps the Docker workflow so the bundled PostgreSQL can be started, queried, and used for trace collection with much less setup friction.

## Why This Exists

The course is built around reading PostgreSQL execution traces, not just SQL results or `EXPLAIN` output.

This helper script exists to make it easier to:

- run the bundled trace-enabled PostgreSQL build in Docker
- initialize and reset a test database quickly
- run SQL interactively or from `.sql` files
- clear the trace log before each experiment
- fetch the generated trace log back to the host for study

This is useful when you want a repeatable workflow while going through the lessons, especially on systems like Manjaro where the bundled binaries may not run cleanly on the host without compatibility work.

## What `trace.sh` Does

`trace.sh` starts the course PostgreSQL build inside a `centos:7` container and mounts the current repository into the container at `/work`.

It manages:

- the PostgreSQL data directory: `./pgdata`
- the Docker container: `pgtrace`
- the live trace file inside the container: `/home/pguser/trace.log`
- the fetched host copy of the trace: `./trace.log`

The important detail is that PostgreSQL writes the live trace inside the container user home, not directly into the repository root. The `fetch` command copies it back to `./trace.log` on the host.

## Repository Layout

Expected files and directories:

- `trace.sh`: helper script for Docker and trace workflow
- `pgsql/`: bundled trace-enabled PostgreSQL distribution from the course
- `pgdata/`: initialized PostgreSQL cluster data directory
- `trace.log`: fetched trace log copied from the container
- `*.sql`: optional SQL files for repeatable experiments
- `lessons/`, `traces/`, `readme.html`: original course materials

## Prerequisites

- Docker installed and working
- the course PostgreSQL package extracted so that `./pgsql/bin/postgres` exists
- `trace.sh` marked executable

Make the script executable once:

```bash
chmod +x ./trace.sh
```

## Quick Start

Initialize the database, start PostgreSQL, run a query, and fetch the trace:

```bash
./trace.sh init
./trace.sh start
./trace.sh clear
./trace.sh run "select version();"
./trace.sh fetch
less ./trace.log
```

For interactive work:

```bash
./trace.sh psql
```

Then inside `psql`:

```sql
create table if not exists t(id int);
insert into t values (1);
select * from t where id = 1;
```

After that:

```bash
./trace.sh fetch
less ./trace.log
```

## Commands

Show the built-in help:

```bash
./trace.sh help
```

Available commands:

- `./trace.sh help`
  Show available commands and examples.

- `./trace.sh init`
  Initialize `./pgdata` if it does not already exist.

- `./trace.sh start`
  Start the PostgreSQL trace container if it is not already running.

- `./trace.sh restart`
  Stop the container, delete and recreate `./pgdata`, remove the host `./trace.log`, and start fresh. Use this when you want a clean environment from scratch.

- `./trace.sh stop`
  Stop the running PostgreSQL trace container.

- `./trace.sh status`
  Show the Docker container status.

- `./trace.sh psql`
  Open an interactive `psql` session inside the container.

- `./trace.sh run "SQL"`
  Run one SQL statement non-interactively.

- `./trace.sh runfile ./example.sql`
  Run SQL from a file. The file must be inside this repository so it is visible from the mounted container path.

- `./trace.sh clear`
  Clear the live trace log inside the container.

- `./trace.sh fetch`
  Copy the live trace log from the container to `./trace.log` on the host.

- `./trace.sh tail`
  Show the last 40 lines of the live trace file inside the container.

- `./trace.sh logs`
  Show PostgreSQL container logs.

## Recommended Workflow For Course Lessons

When you want to reproduce a lesson or test a small idea:

1. Start clean if needed:

```bash
./trace.sh restart
```

2. Clear the trace before the specific SQL you care about:

```bash
./trace.sh clear
```

3. Run SQL using either interactive `psql`, `run`, or `runfile`.

4. Fetch the trace:

```bash
./trace.sh fetch
```

5. Read `./trace.log` side by side with the matching course lesson.

This keeps the collected trace focused on the exact operation you want to study.

## Example With A SQL File

Create a file such as `example.sql` in this repository:

```sql
create table if not exists t(id int primary key, v text);
insert into t values (1, 'a') on conflict do nothing;
select * from t where id = 1;
```

Then run:

```bash
./trace.sh restart
./trace.sh clear
./trace.sh runfile ./example.sql
./trace.sh fetch
less ./trace.log
```

## Trace Location

There are two trace locations involved:

- live trace inside the container: `/home/pguser/trace.log`
- fetched host copy: `./trace.log`

If you inspect `./trace.log` on the host before running `fetch`, it may be missing or stale. `fetch` is the step that copies the latest trace from the running container into the repository.

## Course Context

The best lessons to read first for understanding the trace output itself are:

- `Lesson 2. Inside PostgreSQL Unlocking Secrets with Trace Analysis`
- `Lesson 58. Trace Analysis: Understanding Its Power and Limitations`

In short:

- Lesson 2 explains the trace format and how to read function entry, exit, stack depth, and `info:` lines.
- Lesson 58 explains why tracing is valuable and what its limitations are.

The provided `traces/` directory contains sample traces from the course, while the bundled PostgreSQL build and `trace.sh` let you generate your own traces for experiments.

## Notes

- `restart` is destructive for `./pgdata`. It is meant for clean experiments.
- `runfile` only works for files inside the repository root.
- `trace.sh` resolves the repository root from its own location, so you can move this repository without editing the script.

## License And Course Materials

This repository is only a helper around the course materials you already own. If you need the original course, see [`PostgreSQL Uncovered`](https://wangbin579.gumroad.com/l/postgresql_course).

Respect the original course license and distribution terms for lesson files, bundled binaries, and traces.
