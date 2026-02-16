FROM alpine:3.21

# Install curl for API calls
RUN apk add --no-cache curl bash

# Copy scripts
COPY backup.sh /backup.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /backup.sh /entrypoint.sh

# Create backup directory
RUN mkdir -p /backups

# Environment defaults
ENV BACKUP_DIR=/backups
ENV BACKUP_HOUR=3
ENV BACKUP_MINUTE=0

# Volume for persistent backups
VOLUME ["/backups"]

ENTRYPOINT ["/entrypoint.sh"]
