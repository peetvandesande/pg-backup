FROM alpine:3

# Install only client tooling (no postgres server)
# - postgresql-client: psql, pg_dump
# - dcron: lightweight cron
# - coreutils: for date, ls behavior, sha256sum
# - gzip, bzip2, zstd: compression support
RUN apk add --no-cache \
      postgresql-client \
      dcron \
      coreutils \
      gzip \
      bzip2 \
      zstd \
 && mkdir -p /etc/crontabs \
 && echo '0	2	*	*	*	/usr/local/bin/backup >> /proc/1/fd/1 2>&1' >> /etc/crontabs/root \
 && chmod 600 /etc/crontabs/root

# Copy scripts from repo root 'app/' and make them executable
COPY --chmod=0755 app/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 app/backup.sh     /usr/local/bin/backup
COPY --chmod=0755 app/restore.sh    /usr/local/bin/restore

VOLUME [ "/backups" ]

ENTRYPOINT [ "/entrypoint.sh" ]

