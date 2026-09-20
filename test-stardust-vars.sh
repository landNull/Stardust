#!/bin/sh
# test-stardust-vars.sh — Pre-flight structural validator for Stardust variables
set -eu

PROG=${0##*/}
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

echo "===================================================="
echo "🔍 Starting Stardust Configuration Hand-Off Audit..."
echo "===================================================="

REQUIRED_VARS="DRYRUN ROLE OWNER ADMIN GROUP PLATFORMS STARDUST PKG INIT OS_ID SVC_APACHE SVC_DB"

DRYRUN=1; ROLE="devel"; OWNER="deploy"; ADMIN="www-admin"; GROUP="www-admin"
PLATFORMS="/srv/platforms"; STARDUST="/srv/stardust"; PKG="apt"; INIT="systemd"
OS_ID="debian"; SVC_APACHE="apache2"; SVC_DB="mariadb"

audit_environment() {
  target_module="$1"
  status_flag=0
  echo "📋 Auditing state tracking for module: [$(basename "$target_module")]"
  for var_name in $REQUIRED_VARS; do
    eval var_val=\${$var_name:-}
    if [ -z "$var_val" ]; then
      echo "  ❌ CRITICAL FAILURE: Variable [\$$var_name] is empty or unassigned!" >&2
      status_flag=1
    else
      echo "  ✓ Hand-off verified: \$$var_name = $var_val"
    fi
  done
  return $status_flag
}

failures=0
if [ -d "$HERE/modules" ]; then
  for module in "$HERE/modules/"[0-9][0-9]-*.sh; do
    if [ -f "$module" ]; then
      audit_environment "$module" || failures=$((failures + 1))
    fi
  done
else
  echo "❌ Error: The modules/ directory could not be located." >&2
  exit 1
fi

echo "===================================================="
if [ "$failures" -eq 0 ]; then
  echo "✅ PASS: All global environment variables handed off successfully!"
  exit 0
else
  echo "❌ FAIL: Detected $failures validation gaps in your configuration tracking." >&2
  exit 1
fi
