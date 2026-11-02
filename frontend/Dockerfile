# Frontend tier: static page + nginx reverse proxy to the API VM.
# nginx-unprivileged runs as a non-root user and listens on 8080. Its
# entrypoint runs envsubst on /etc/nginx/templates/*.template at start-up,
# filling in API_UPSTREAM (set on the container app by Terraform).
FROM nginxinc/nginx-unprivileged:1.31-alpine

COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY site/ /usr/share/nginx/html/

USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
