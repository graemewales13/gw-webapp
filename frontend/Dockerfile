# Frontend tier: static page + nginx reverse proxy to the API VM.
# nginx-unprivileged runs as a non-root user and listens on 8080. Its
# entrypoint runs envsubst on /etc/nginx/templates/*.template at start-up,
# filling in API_UPSTREAM (set on the container app by Terraform).
FROM nginxinc/nginx-unprivileged:1.31-alpine

# Install Alpine's security fixes now rather than waiting for the next
# nginx image rebuild (Trivy fails the build on fixable critical CVEs).
# Builds on different days can get different package versions; that's the
# accepted trade-off. The container still runs as the non-root user 101.
USER 0
# hadolint ignore=DL3017
RUN apk upgrade --no-cache

COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY site/ /usr/share/nginx/html/

USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
