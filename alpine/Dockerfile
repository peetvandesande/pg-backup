FROM postgres:17-alpine

RUN apk add --no-cache \
      dcron

# Copy scripts from repo root 'app/' and make them executable
COPY --chmod=0755 app/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 app/backup.sh /usr/local/bin/backup
COPY --chmod=0755 app/restore.sh /usr/local/bin/restore

# Install cron job
COPY --chmod=0644 alpine/crontab /etc/crontabs/root

VOLUME [ "/backups" ]

ENTRYPOINT [ "/entrypoint.sh" ]

