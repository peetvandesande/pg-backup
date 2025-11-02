FROM postgres:17-alpine

RUN apk add --no-cache \
      coreutils \
 && mkdir -p /etc/crontabs \
 && echo '30	10	*	*	*	/usr/local/bin/backup >> /proc/1/fd/1 2>&1' >> /etc/crontabs/root \
 && chmod 600 /etc/crontabs/root

# Copy scripts from repo root 'app/' and make them executable
COPY --chmod=0755 app/entrypoint.sh /entrypoint.sh
COPY --chmod=0755 app/backup.sh     /usr/local/bin/backup
COPY --chmod=0755 app/restore.sh    /usr/local/bin/restore

VOLUME [ "/backups" ]

ENTRYPOINT [ "/entrypoint.sh" ]

