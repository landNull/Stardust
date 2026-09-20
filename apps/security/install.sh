#!/bin/sh
# modules/35-security.sh — extras, VPS sysctl/limits, optional CSF
# Certbot is not installed here. Do not rewrite WireGuard.

echo "STEP 35: extras, VPS harden, CSF"

tune_extras
tune_vps
setup_csf
