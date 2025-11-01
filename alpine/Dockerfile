FROM postgres:17-alpine

RUN apk add --no-cache dcron tzdata

# Copy scripts from repo root 'app/' and make them executable
COPY --chmod=0755 app/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 app/pg-backup.sh  /usr/local/bin/pg-backup
COPY --chmod=0755 app/pg-restore.sh /usr/local/bin/pg-restore

# Install cron job
COPY --chmod=0644 alpine/crontab /etc/crontabs/root

VOLUME [ "/backups" ]

ENV BACKUPS_DIR=/backups

ENTRYPOINT [ "/entrypoint.sh" ]