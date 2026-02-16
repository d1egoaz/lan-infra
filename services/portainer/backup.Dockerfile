FROM alpine:3.21

RUN apk add --no-cache \
    restic \
    curl \
    tzdata

COPY backup.sh /usr/local/bin/
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/entrypoint.sh

ENV BACKUP_SCHEDULE="0 3 * * *"
ENV PORTAINER_API_URL="http://portainer:9000/api"
ENV RESTIC_REPOSITORY="/backups"
ENV KEEP_DAILY="7"
ENV KEEP_WEEKLY="4"
ENV KEEP_MONTHLY="3"

VOLUME ["/backups"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
