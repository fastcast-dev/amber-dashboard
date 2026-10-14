#!/usr/bin/env bash
# Creates (or replaces) the amber-dashboard-api Secret: the Amber API key and site id that nginx uses
# to proxy prices. Run by a cluster admin; the key never goes into git, GitHub, argv or shell history.
#
#   deploy/create-secret.sh <kube-context>      e.g. deploy/create-secret.sh k3s-dev
#
# Get a key at https://app.amber.com.au/developers. Rotate by running this again and revoking the old key.
set -euo pipefail

CONTEXT="${1:?usage: $0 <kube-context>}"
NAMESPACE=public
SECRET=amber-dashboard-api

read -rsp "Amber API key (psk_..., input hidden): " AMBER_KEY; echo
# The Secret is included as nginx config, so only accept the exact key format (no quotes/semicolons)
if [[ ! "${AMBER_KEY}" =~ ^psk_[0-9a-fA-F]{16,64}$ ]]; then
  echo "That doesn't look like an Amber key (psk_ followed by hex)." >&2; exit 1
fi

# Look up the site(s). The key goes to curl on stdin (-H @-), never on the command line.
SITES="$(printf 'Authorization: Bearer %s\n' "${AMBER_KEY}" \
  | curl -fsS --proto '=https' -H @- https://api.amber.com.au/v1/sites)" \
  || { echo "Amber rejected the key or couldn't be reached." >&2; exit 1; }
mapfile -t SITE_IDS < <(printf '%s' "${SITES}" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[0-9A-Z]+"' | grep -oE '[0-9A-Z]{10,}')
if [[ ${#SITE_IDS[@]} -eq 0 ]]; then
  echo "No sites on this Amber account." >&2; exit 1
elif [[ ${#SITE_IDS[@]} -gt 1 ]]; then
  echo "Sites on this account:"; printf '  %s\n' "${SITE_IDS[@]}"
  read -rp "Site id to show: " SITE_ID
else
  SITE_ID="${SITE_IDS[0]}"
fi
if [[ ! "${SITE_ID}" =~ ^[0-9A-Z]{10,40}$ ]]; then
  echo "Invalid site id." >&2; exit 1
fi

printf 'set $amber_site_id "%s";\nset $amber_authorization "Bearer %s";\n' "${SITE_ID}" "${AMBER_KEY}" \
  | kubectl --context "${CONTEXT}" -n "${NAMESPACE}" create secret generic "${SECRET}" \
      --from-file=amber.conf=/dev/stdin --dry-run=client -o yaml \
  | kubectl --context "${CONTEXT}" -n "${NAMESPACE}" apply --server-side --force-conflicts \
      --field-manager=amber-dashboard-admin -f - >/dev/null
# (server-side apply: client-side apply would copy the key into a last-applied-configuration
# annotation, which `kubectl describe` prints)
unset AMBER_KEY SITES

echo "Secret ${NAMESPACE}/${SECRET} saved in ${CONTEXT} for site ${SITE_ID}."
if kubectl --context "${CONTEXT}" -n "${NAMESPACE}" get deployment amber-dashboard >/dev/null 2>&1; then
  kubectl --context "${CONTEXT}" -n "${NAMESPACE}" rollout restart deployment/amber-dashboard
  echo "Restarted amber-dashboard to pick it up."
fi
