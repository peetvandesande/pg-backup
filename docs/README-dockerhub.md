# 🐘 pg-backup
[![Docker Pulls](https://img.shields.io/docker/pulls/peetvandesande/pg-backup.svg)](https://hub.docker.com/r/peetvandesande/pg-backup)
[![Image Size](https://img.shields.io/docker/image-size/peetvandesande/pg-backup/alpine)](https://hub.docker.com/r/peetvandesande/pg-backup)

Minimal PostgreSQL backup/restore container based on Alpine. Uses only the PostgreSQL **client** tools — no full server.

---

## 🧩 Features
- Creates timestamped `.sql`, `.sql.gz`, `.sql.zst`, or `.sql.bz2` dumps
- Optional SHA-256 checksum generation
- Can restore the **latest** matching dump automatically
- Works one-off or scheduled using built-in cron
- Supports multiple architectures (via `multiarch` build)

---

## 🏗️ Usage

### One-off backup
```bash
docker run --rm \
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  -e BACKUP_NAME_PREFIX=mydb \
  -e RUN_ONCE=1 \
  peetvandesande/pg-backup:alpine
```

### Restore latest backup
```bash
docker run --rm \
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  peetvandesande/pg-backup:alpine restore
```

### Restore specific file
```bash
peetvandesande/pg-backup:alpine restore /backups/mydb-20250101.sql.gz
```

---

## ⚙️ Environment Variables

| Variable | Required | Default | Meaning |
|---------|----------|---------|---------|
| `POSTGRES_USER` | ✅ | – | Database user |
| `POSTGRES_PASSWORD` | ✅ | – | Database password |
| `POSTGRES_DB` | ✅ | – | Database name |
| `POSTGRES_HOST` | ❌ | `db` | Database host |
| `POSTGRES_PORT` | ❌ | `5432` | Database port |
| `BACKUPS_DIR` | ❌ | `/backups` | Where dumps are stored |
| `BACKUP_NAME_PREFIX` | ❌ | `postgres-$POSTGRES_DB` | Filename prefix |
| `COMPRESS` | ❌ | `gz` | `gz`, `bz2`, `zst`, or `none` |
| `COMPRESS_LEVEL` | ❌ | *(auto)* | Compression level |
| `VERIFY_SHA256` | ❌ | `1` | Create `.sha256` checksum |
| `RUN_ONCE` | ❌ | `0` | Backup once then exit |
| `RUN_BACKUP_ON_START` | ❌ | `0` | Backup at container start before cron |

---

## 📦 Output
```
/backups/
├── mydb-20250101.sql.gz
└── mydb-20250101.sql.gz.sha256
```

---

## Documentation
Full restore workflow (including volume recreation):
→ https://github.com/peetvandesande/pg-backup/docs/postgres-backup-restore.md

---

### Ownership / Permissions

You can optionally set file ownership and/or permissions on the dump files:

```bash
# Force UID=33, keep existing GID
-e CHOWN_UID=33

# Force GID=33, keep existing UID
-e CHOWN_GID=33

# Force both explicitly
-e CHOWN_UID=33 -e CHOWN_GID=33

# Apply file mode to .sql[.*] and .sha256
-e CHMOD_MODE=0640
```
