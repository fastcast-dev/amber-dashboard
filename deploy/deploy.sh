#!/usr/bin/env bash
# Deploys amber-dashboard to the `public` namespace of the cluster in $KUBECONFIG.
#
#   deploy/deploy.sh dev|prod
#
# Used by .github/workflows/deploy-env.yml, and can be run by hand with an admin kubeconfig.
# Never reads or prints the Amber API key: the amber-dashboard-api Secret is created by hand
# in-cluster (see README); this only checks it exists.
set -euo pipefail

ENVIRONMENT="${1:-}"
case "${ENVIRONMENT}" in
  dev | prod) ;;
  *) echo "usage: $0 dev|prod" >&2; exit 2 ;;
esac

NAMESPACE=public
APP=amber-dashboard
SECRET=amber-dashboard-api
FIELD_MANAGER=amber-dashboard-deploy
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${REPO_ROOT}/deploy/k8s/.build"   # gitignored; kustomize only loads files under its own root

log() { echo "==> $*"; }
summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$*" >> "${GITHUB_STEP_SUMMARY}" || true; }

cleanup() { rm -rf "${BUILD}"; }
trap cleanup EXIT

# --- 1. Build: overlay + content-hashed ConfigMaps for public/ and nginx/ ---------------------------
cleanup
mkdir -p "${BUILD}/site" "${BUILD}/nginx"
cp "${REPO_ROOT}"/public/* "${BUILD}/site/"
cp "${REPO_ROOT}"/nginx/default.conf "${REPO_ROOT}"/nginx/security-headers.inc \
   "${REPO_ROOT}"/nginx/resolver.inc "${BUILD}/nginx/"

# Restart the pod when the Secret is rotated (nginx only reads it at startup). Only the
# resourceVersion is printed - never the Secret's data.
if SECRET_VERSION="$(kubectl -n "${NAMESPACE}" get secret "${SECRET}" -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null)"; then
  log "Secret ${SECRET} present (resourceVersion ${SECRET_VERSION})"
else
  SECRET_VERSION="missing"
  echo "::warning::Secret ${NAMESPACE}/${SECRET} doesn't exist yet: the dashboard will deploy but show" \
       "\"no API key set up\". Create it as described in the README."
fi

{
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  echo "namespace: ${NAMESPACE}"
  echo "resources:"
  echo "  - ../overlays/${ENVIRONMENT}"
  echo "generatorOptions:"
  echo "  labels:"
  echo "    app.kubernetes.io/name: ${APP}"
  echo "    app.kubernetes.io/component: content"
  echo "configMapGenerator:"
  echo "  - name: ${APP}-site"
  echo "    files:"
  for f in "${BUILD}"/site/*; do echo "      - site/$(basename "${f}")"; done
  echo "  - name: ${APP}-nginx"
  echo "    files:"
  for f in "${BUILD}"/nginx/*; do echo "      - nginx/$(basename "${f}")"; done
  echo "patches:"
  echo "  - target:"
  echo "      kind: Deployment"
  echo "      name: ${APP}"
  echo "    patch: |-"
  echo "      - op: add"
  echo "        path: /spec/template/metadata/annotations"
  echo "        value:"
  echo "          amber-dashboard/secret-version: \"${SECRET_VERSION}\""
} > "${BUILD}/kustomization.yaml"

kubectl kustomize "${BUILD}" > "${BUILD}/rendered.yaml"
log "Rendered $(grep -c '^kind:' "${BUILD}/rendered.yaml") objects for ${ENVIRONMENT}"

# --- 2. Apply ----------------------------------------------------------------------------------------
# Server-side apply: the site ConfigMap is too big for client-side apply's last-applied annotation.
apply() {
  kubectl apply --server-side --force-conflicts --field-manager="${FIELD_MANAGER}" "$@" -f "${BUILD}/rendered.yaml"
}
log "Server-side dry run"
apply --dry-run=server
log "Applying"
apply

log "Waiting for rollout"
if ! kubectl -n "${NAMESPACE}" rollout status "deployment/${APP}" --timeout=180s; then
  echo "::error::Rollout didn't become ready; the previous pod is still serving (maxUnavailable: 0)."
  kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/name=${APP}" -o wide || true
  kubectl -n "${NAMESPACE}" get events --field-selector "involvedObject.kind=Pod" \
    --sort-by=.lastTimestamp 2>/dev/null | tail -20 || true
  exit 1
fi
kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/name=${APP}" -o wide

# --- 3. Prune content ConfigMaps no ReplicaSet uses any more (keeps `rollout undo` working) ---------
in_use="$(kubectl -n "${NAMESPACE}" get replicasets -l "app.kubernetes.io/name=${APP}" \
  -o jsonpath='{range .items[*]}{range .spec.template.spec.volumes[*]}{.configMap.name}{"\n"}{end}{end}' \
  | grep -v '^$' | sort -u || true)"
if [[ -n "${in_use}" ]]; then
  stale="$(kubectl -n "${NAMESPACE}" get configmaps -l "app.kubernetes.io/name=${APP},app.kubernetes.io/component=content" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -v '^$' | grep -Fxv -f <(printf '%s\n' "${in_use}") || true)"
  for name in ${stale}; do
    log "Pruning unused ConfigMap ${name}"
    kubectl -n "${NAMESPACE}" delete configmap "${name}" --wait=false
  done
fi

IMAGE="$(kubectl -n "${NAMESPACE}" get deployment "${APP}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
HOST="$(kubectl -n "${NAMESPACE}" get ingress "${APP}" -o jsonpath='{.spec.rules[0].host}')"
summary "### amber-dashboard → ${ENVIRONMENT}"
summary ""
summary "| | |"
summary "|---|---|"
summary "| Host | https://${HOST} |"
summary "| Image | \`${IMAGE}\` |"
summary "| API key Secret | $([[ "${SECRET_VERSION}" == missing ]] && echo "⚠️ missing" || echo "present") |"
log "Done: https://${HOST}"
