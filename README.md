# pg-backup
Docker container to run as a sidecar and backup PostgreSQL.

This image is expected to run alongside a PostgreSQL database container; it does not create its own database and expects the following environment variables:
-   POSTGRES_PASSWORD
-   POSTGRES_USER
-   POSTGRES_DB
-   POSTGRES_HOST

# Branches

The `main` branch uses the Alpine-based image to keep things small. This branch is used to produce images with tags `:17`, `:17-latest` and `:17-alpine`.

The `debian-host` branch uses the Debian based image, which has a backup:backup user by default with uid:gid of 34:34. Use the tag `:17-debian` to select this image.

Functionality between the branches is the same.

# How to use this image

This container takes one daily backup (scheduled by `cron`) and stores it into the /backup directory.

From there you can manage the backup files yourself (e.g. rotate or delete older files).

By default, the backup script gzips the output and the restore script expects gzipped files too.  
If you change one script, update the other accordingly.

## Building the image
```console
docker build -t pg-backup .
```

## Pulling an existing image

### Using `docker run` to backup

We will bind mount a local directory to be used by the container:

For example:
-   `/my/path/backup` → backup storage directory

Make sure these directories exist.

Run the container:
```console
docker run -d --name pg-backup \
  -v /my/path/backup:/backup \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_HOST=db \
  pg-backup
```

This starts the cron-based backup process in the background.

### Using `docker run` to restore

The restore process has the same requirements as backup (same environment variables and mounts).
By default, `pg-restore` will restore yesterday’s backup. You can also specify a particular file.

Example: restore yesterday’s backup file explicitly (GNU `date` syntax):

```console
docker run --rm --name pg-restore \
  -v /my/path/backup:/backup \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_HOST=db \
  pg-backup \
  pg-restore "/backup/appdb-$(date -d 'yesterday' +%Y%m%d).sql.gz"
```

- `--rm` ensures the container is cleaned up after the restore finishes.
- You can omit the filename to let the script pick yesterday’s file automatically:

```console
docker run --rm --name pg-restore \
  -v /my/path/backup:/backup \
  -e POSTGRES_USER=user \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=appdb \
  -e POSTGRES_HOST=db \
  pg-backup \
  pg-restore
```

### Using `docker-compose`

You can run this container alongside your PostgreSQL service using Docker Compose.
It will follow the schedule defined in the crontab inside the image.

Here’s a minimal example:

```yaml
services:
  # The container that runs the database (postgres)
  db:
    image: "postgres:17"
    container_name: postgres-db
    restart: unless-stopped
    environment:
      - POSTGRES_ROOT_PASSWORD=rootsecret
      - POSTGRES_PASSWORD=secret
      - POSTGRES_USER=user
      - POSTGRES_DB=appdb
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale-provider=builtin --locale=C.UTF-8
    volumes:
      - postgres-data:/var/lib/postgresql/data

  # The container that runs the backup procedure
  pg-backup:
    image: peetvandesande/pg-backup:17
    container_name: postgres-backup
    environment:
      - POSTGRES_PASSWORD=secret
      - POSTGRES_USER=user
      - POSTGRES_DB=appdb
      - POSTGRES_HOST=db
    volumes:
      - pg-backup:/backup

volumes:
  postgres-data: {}
  pg-backup: {}
```
