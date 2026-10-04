#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-credentials.sh
. "$ROOT/scripts/lib-credentials.sh"
[[ -f /etc/x-ui/x-ui.db ]] || exit 0
create_api_token
[[ -n "${API_TOKEN:-}" ]] || exit 0
upsert_install_result_kv XUI_API_TOKEN "$API_TOKEN"
