#!/usr/bin/env bash
# Builds the example, installs it on a simulator and opens the Trade tab with trade.local.env as its
# launch environment (SIMCTL_CHILD_*). The file is gitignored and holds a key: no value is ever printed.
#
# Usage, from the example folder:
#   cp trade.local.env.example trade.local.env   # then put the test user's values in it
#   tools/run-trade.sh
# WIREX_SIMULATOR=<udid> picks the simulator when more than one is booted.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ENV_FILE="trade.local.env"
ALLOWED="WIREX_ENVIRONMENT WIREX_CHAIN_ID WIREX_COMPANY_ID WIREX_OWNER_KEY WIREX_BAAS_API_URL"

die() { printf '%s\n' "$*" >&2; exit 1; }

[[ -f "${ENV_FILE}" ]] || die "no ${ENV_FILE}: copy trade.local.env.example and fill it in"
git check-ignore -q "${ENV_FILE}" || die "${ENV_FILE} is not gitignored: refusing to read a key from a file git would track"

set_names=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -z "${line// }" || "${line}" == \#* ]] && continue
  name="${line%%=*}"
  value="${line#*=}"
  [[ " ${ALLOWED} " == *" ${name} "* ]] || die "unknown name in ${ENV_FILE}: ${name}"
  [[ -n "${value}" ]] || continue
  export "SIMCTL_CHILD_${name}=${value}"
  set_names+=("${name}")
done < "${ENV_FILE}"
printf 'launch environment: %s\n' "${set_names[*]:-none}"

[[ -d WirexMobileSdkExample.xcodeproj ]] || xcodegen generate --quiet

DEVICE="${WIREX_SIMULATOR:-$(xcrun simctl list devices booted | sed -nE 's/.*\(([0-9A-F-]{36})\) \(Booted\).*/\1/p' | head -1)}"
[[ -n "${DEVICE}" ]] || die "no booted simulator: boot one, or set WIREX_SIMULATOR"

DERIVED="${TMPDIR:-/tmp}/wirex-mobile-example-ios"
xcodebuild -project WirexMobileSdkExample.xcodeproj -scheme WirexMobileSdkExample \
  -destination "platform=iOS Simulator,id=${DEVICE}" -derivedDataPath "${DERIVED}" \
  -configuration Debug -quiet build
xcrun simctl install "${DEVICE}" "${DERIVED}/Build/Products/Debug-iphonesimulator/WirexMobileSdkExample.app"
xcrun simctl launch --terminate-running-process "${DEVICE}" com.wirexapp.baas.example.ios -wirexScreen trade >/dev/null
printf 'running on %s\n' "${DEVICE}"
