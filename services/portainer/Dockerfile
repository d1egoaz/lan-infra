FROM alpine:3.21

RUN apk add --no-cache curl tzdata findutils util-linux coreutils bash dcron vim procps

# Create backup user (non-root)
RUN adduser -D -s /bin/sh backup && \
    mkdir -p /backups /scripts && \
    chown backup:backup /backups

COPY --chmod=755 backup.sh entrypoint.sh /scripts/

USER backup
WORKDIR /backups
VOLUME ["/backups"]

HEALTHCHECK --interval=1m --timeout=10s --start-period=30s \
    CMD pgrep crond >/dev/null || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
