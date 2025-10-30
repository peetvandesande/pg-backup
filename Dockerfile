FROM postgres:17-alpine

RUN apk add --no-cache bash coreutils dcron tzdata

WORKDIR /

# Copy the scripts into the container and make them executable
COPY --chmod=0755 pg-backup.sh  /usr/local/bin/pg-backup
COPY --chmod=0755 pg-restore.sh /usr/local/bin/pg-restore

# Install cron job
COPY --chmod=0644 crontab /etc/crontabs/root

# Run cron in the foreground so Docker handles logs & lifecycle
CMD ["crond", "-f", "-L", "/dev/stdout"]
