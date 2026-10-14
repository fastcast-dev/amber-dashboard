#!/usr/bin/env bash
# Sets the KUBECONFIG environment secret the deploy workflow uses, built from the cluster's long-lived
# github-deployer-token (k3s-deploys: docs/github-deploy-credentials.md). The token goes straight from
# kubectl into `gh secret set`; it's never printed or written to disk. Re-run after rotating the token.
#
#   deploy/set-github-kubeconfig.sh dev k3s-dev
#   deploy/set-github-kubeconfig.sh prod k3s-prod
set -euo pipefail

ENVIRONMENT="${1:?usage: $0 <github-environment> <kube-context>}"
CONTEXT="${2:?usage: $0 <github-environment> <kube-context>}"
REPO="${REPO:-fastcast-dev/amber-dashboard}"

CA="$(kubectl --context "${CONTEXT}" -n public get secret github-deployer-token -o jsonpath='{.data.ca\.crt}')"
TOKEN="$(kubectl --context "${CONTEXT}" -n public get secret github-deployer-token -o jsonpath='{.data.token}' | base64 -d)"
[[ -n "${CA}" && -n "${TOKEN}" ]] || { echo "github-deployer-token in ${CONTEXT} is empty" >&2; exit 1; }

# In-cluster runners: the server is always the cluster's own API (a dev job can only reach dev)
printf 'apiVersion: v1\nkind: Config\nclusters:\n- name: k3s\n  cluster:\n    server: https://kubernetes.default.svc\n    certificate-authority-data: %s\ncontexts:\n- name: deploy\n  context:\n    cluster: k3s\n    user: github-deployer\n    namespace: public\ncurrent-context: deploy\nusers:\n- name: github-deployer\n  user:\n    token: %s\n' \
  "${CA}" "${TOKEN}" | base64 -w0 | gh secret set KUBECONFIG --env "${ENVIRONMENT}" --repo "${REPO}"
unset TOKEN
echo "Set KUBECONFIG on ${REPO} environment '${ENVIRONMENT}' from ${CONTEXT}."
