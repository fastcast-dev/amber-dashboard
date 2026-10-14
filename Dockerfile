# Local preview of the dashboard on Chainguard's nginx (distroless: non-root uid 65532, no shell,
# listens on 8080). The clusters don't use this image: they run the same digest-pinned base image
# with public/ and nginx/ mounted from ConfigMaps (see deploy/ and .github/workflows/).
#
#   docker build -t amber-dashboard .
#   docker run --rm -p 8080:8080 -v "$PWD/amber.conf:/etc/nginx/amber/amber.conf:ro" amber-dashboard
#
# amber.conf holds the Amber API key (template: deploy/amber.conf.example). It's mounted at run time,
# never baked into the image.
FROM fastcast-dev.self-hosted.io/cgr/nginx:1.31@sha256:4d28bb935112fdab6ee87ef7b21eef5f47313e160806316be19262a9228132a5

COPY nginx/default.conf /etc/nginx/conf.d/nginx.default.conf
COPY nginx/security-headers.inc /etc/nginx/conf.d/security-headers.inc
COPY nginx/docker/resolver.inc /etc/nginx/conf.d/resolver.inc
# Own directory: the image's default web root has index.html symlinked to a welcome page
COPY public/ /usr/share/nginx/dashboard/

EXPOSE 8080
