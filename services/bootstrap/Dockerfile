# One-shot job that claims a fresh Infisical instance (see bootstrap.sh).
FROM curlimages/curl:8.22.0

COPY bootstrap.sh /bootstrap.sh

RUN sh -n /bootstrap.sh

ENTRYPOINT ["/bin/sh", "/bootstrap.sh"]
