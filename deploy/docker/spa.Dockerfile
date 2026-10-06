# syntax=docker/dockerfile:1
# SPA deployables (spec platform v1 §1): Vite build → nginx-unprivileged. /config.js comes only from a ConfigMap (the dev public/config.js is dropped from dist).
#   docker buildx build --load -f deploy/docker/spa.Dockerfile --build-arg APP=web-customer -t banking-go/web-customer:local .
ARG NODE_IMAGE=node:24.19.0-trixie-slim
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:1.30.5-alpine

FROM ${NODE_IMAGE} AS build
ARG APP
ENV CI=true
WORKDIR /src
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY packages/ packages/
COPY apps/ apps/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    test -n "$APP" && \
    npx -y pnpm@12.9.1 install --frozen-lockfile --filter "@banking-go/${APP}..." && \
    npx -y pnpm@12.9.1 --filter "@banking-go/${APP}" build && \
    rm -f "apps/${APP}/dist/config.js"

FROM ${NGINX_IMAGE}
ARG APP
USER root
RUN rm -f /etc/nginx/conf.d/default.conf
COPY deploy/docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY deploy/docker/nginx/default.conf.template deploy/docker/nginx/security-headers.inc.template /etc/nginx/templates/
COPY --from=build /src/apps/${APP}/dist/ /usr/share/nginx/html/
ENV NGINX_ENVSUBST_OUTPUT_DIR=/tmp NGINX_ENVSUBST_TEMPLATE_SUFFIX=.template BG_API_ORIGIN=http://localhost:8081
USER 101
EXPOSE 8080
