
# 🐘 pg-backup
[![Docker Pulls](https://img.shields.io/docker/pulls/peetvandesande/pg-backup.svg)](https://hub.docker.com/r/peetvandesande/pg-backup)
[![Image Size](https://img.shields.io/docker/image-size/peetvandesande/pg-backup/alpine)](https://hub.docker.com/r/peetvandesande/pg-backup)
[![GitHub](https://img.shields.io/badge/source-github-blue)](https://github.com/peetvandesande/file-backup)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](https://github.com/peetvandesande/pg-backup/blob/main/LICENSE)

Lightweight PostgreSQL backup container that creates timestamped database dumps.  
No rotation, pruning, encryption, or cloud upload — **bring your own retention policy.**

---

## 🚀 Quick Usage

### One-off backup

```bash
docker run --rm \
  --network app_default \       # Needed to connect to PostgreSQL server
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  -e BACKUP_NAME_PREFIX=mydb \
  -e RUN_ONCE=1 \
  peetvandesande/pg-backup:alpine
```

### Scheduled backup ( daily at 02:00 by default )

```bash
docker run -d --name pg-backup \
  --network app_default \
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  -e BACKUP_NAME_PREFIX=mydb \
  peetvandesande/pg-backup:alpine
```

Override schedule:
```bash
-v ./crontab:/etc/crontabs/root:ro
```

To run a backup before cron starts:
```bash
-e RUN_BACKUP_ON_START=1
```

---

## 🧰 Restore

Restore the **latest matching** dump:

```bash
docker run --rm \
  --network app_default \
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  peetvandesande/pg-backup:alpine restore
```

Restore a **specific** dump file:

```bash
docker run --rm \
  --network app_default \
  -v /var/backups:/backups \
  -e POSTGRES_HOST=db \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_PASSWORD=mypass \
  -e POSTGRES_DB=mydb \
  peetvandesande/pg-backup:alpine restore /backups/mydb-20251106.sql.gz
```

---

## ⚙️ Environment Variables

| Variable | Default | Description |
|---------|---------|-------------|
| `POSTGRES_USER` | **required** | PostgreSQL username |
| `POSTGRES_PASSWORD` | **required** | PostgreSQL password |
| `POSTGRES_DB` | **required** | Database name to dump |
| `POSTGRES_HOST` | `db` | Hostname or container name of PostgreSQL server |
| `POSTGRES_PORT` | `5432` | PostgreSQL port |
| `BACKUP_NAME_PREFIX` | `postgres-$POSTGRES_DB` | Prefix for dump filenames |
| `BACKUPS_DIR` | `/backups` | Directory for dump storage |
| `COMPRESS` | `gz` | Compression type: `gz`, `bz2`, `zst`, or `none` |
| `COMPRESS_LEVEL` | *(auto)* | Compression level for selected compressor |
| `VERIFY_SHA256` | `1` | `1` = write `.sha256` checksum file |
| `PRESERVE_TIMES` | `1` | Preserve timestamps when creating archives |
| `CHOWN_UID` | *(unset)* | Apply user ownership (if set) |
| `CHOWN_GID` | *(unset)* | Apply group ownership (if set) |
| `CHMOD_MODE` | *(unset)* | Apply mode to dump and checksum files e.g. `0640` |
| `RUN_ONCE` | `0` | Run backup once and exit |
| `RUN_BACKUP_ON_START` | `0` | Run backup before cron starts |

### Ownership Logic Example

```bash
# Force UID=34, keep existing GID:
-e CHOWN_UID=34

# Force GID=34, keep existing UID:
-e CHOWN_GID=34

# Force both explicitly:
-e CHOWN_UID=34 -e CHOWN_GID=34
```

---

## 📦 Output Format

```
/backups/
├── mydb-postgres-20251106.sql.gz
└── mydb-postgres-20251106.sql.gz.sha256
```

---

## 🏷️ Tags

| Tag | Description |
|-----|-------------|
| `alpine` (default) | Smallest runtime image |
| `dev` | Work-in-progress branch images |
| `<version>` | Tagged stable releases |

---

## 🐳 Docker Compose Example

```yaml
services:
  pg-backup:
    image: peetvandesande/pg-backup:alpine
    environment:
      POSTGRES_HOST: db
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypass
      POSTGRES_DB: mydb
      BACKUP_NAME_PREFIX: mydb-postgres
      COMPRESS: gz
      VERIFY_SHA256: 1
    volumes:
      - ./backups:/backups
    depends_on:
      - db

  db:
    image: postgres:17-alpine
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypass
      POSTGRES_DB: mydb
    volumes:
      - ./data:/var/lib/postgresql/data
```

This setup runs a PostgreSQL container and a backup container side by side,  
with backups stored under `./backups` on the host.


---

Full docs and restore guide available here:  
→ https://github.com/peetvandesande/pg-backup/tree/main/docs/
