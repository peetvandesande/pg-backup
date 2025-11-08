# pg-backup

[![Docker Pulls](https://img.shields.io/docker/pulls/peetvandesande/pg-backup)](https://hub.docker.com/r/peetvandesande/pg-backup)
[![Image Size](https://img.shields.io/docker/image-size/peetvandesande/pg-backup/alpine)](https://hub.docker.com/r/peetvandesande/pg-backup/alpine)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/peetvandesande/pg-backup)](https://github.com/peetvandesande/pg-backup/commits/main)
[![GitHub Stars](https://img.shields.io/github/stars/peetvandesande/pg-backup?style=flat)](https://github.com/peetvandesande/pg-backup/stargazers)

Minimal. Deterministic. Boring in the *good* way.

`pg-backup` is a dead-simple PostgreSQL backup container that produces timestamped `.sql`, `.sql.gz`, `.sql.zst`, or `.sql.bz2` dumps. It does **not** manage retention, replication, PITR timelines, or streaming archives. It just **makes the database dump you told it to make** — every time — the same way.

This makes it ideal for:

- Backing up containers before upgrades
- Capturing DB state in CI pipelines
- Homelab durability without operational overhead
- Systems where *transparent* backups are preferred over magic layers

If you want WAL shipping / PITR / LVM / ZFS / continuous backup — use **pgBackRest**, **Patroni**, **Stolon**, or **barman**.  
If you want *one portable, predictable backup job in one container* — use this.

---

## How it Works (at a glance)

```
backup.sh     → pg_dump with compression + optional checksum
restore.sh    → restore the newest matching dump (or one you provide)
entrypoint.sh → supports cron OR one-shot invocation
```

Everything is POSIX `sh`, Alpine-based, client-only — no PostgreSQL server included.  
No daemons. No binaries hidden behind wrappers. No surprises.

---

## Runtime Usage, Env Variables, and Examples

See the Docker Hub page (this is where the usage docs live):

→ https://hub.docker.com/r/peetvandesande/pg-backup

This keeps the GitHub README focused on design and contribution rather than deployment examples.

---

## Tag & Version Strategy

| Branch | Image Tag(s) | Notes |
|--------|-------------|-------|
| `main` | `latest`, `<version>`, `<version>-alpine`, `<sha>` | Always stable |
| `dev`  | `dev`, `dev-alpine`, `dev-<sha>` | Safe for testing / staging |
| feature branches | `<branch>`, `<branch>-alpine`, `<branch>-<sha>` | Useful in CI and migration pipelines |

You always know **exactly** what image you’re running.  
Yes, this is intentional.

---

## Local Development

Clone and build:
```bash
git clone https://github.com/peetvandesande/pg-backup.git
cd pg-backup

make print       # show tags + git metadata
make build       # build multiarch image locally
make push        # push if configured
```

Run test backup locally:

```bash
docker run --rm \
  --network app_default \
  -v $PWD/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=testdb \
  -e RUN_ONCE=1 \
  peetvandesande/pg-backup:dev
```

---

### Documentation

| Topic | Link |
|------|------|
| PostgreSQL Backup & Restore Guide | `docs/postgres-backup-restore.md` |

---

## Philosophy

> **Predictability > Cleverness**

- Backups should be reproducible and explainable.
- Restores should not require detective work.
- Complexity belongs in retention/replication layers, not the backup job itself.

You can chain this container with:
- `rclone` → offsite push (S3 / Wasabi / B2 / MinIO)
- `restic` → dedupe + encryption + retention
- `syncthing` → multi-node sync
- `borg` → encrypted deduplicated archival

But this container itself stays **small, legible, and uninteresting**.  
(That’s a compliment.)

---

## License

**GPL-3.0**

See `LICENSE` in this repository.

---

## Maintainer

**Peet van de Sande**  
https://github.com/peetvandesande

Feel free to open PRs, file issues, or treat this like infrastructure legos.
