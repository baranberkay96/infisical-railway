#!/bin/sh
# One-shot job: claim a fresh Infisical instance for the deployer.
#
# A new Infisical instance lets the first visitor create the super-admin account. This job
# closes that window by calling Infisical's instance bootstrap API right after the server is
# up, creating the admin user and the first organization from template variables:
#
#   GET  /api/status               readiness
#   POST /api/v1/admin/bootstrap   {email, password, organization}
#
# Idempotent: "Instance has already been set up" (HTTP 400) exits 0. The API also returns a
# machine-identity token; it is discarded and never printed.
# Exits non-zero on unexpected answers so Railway's ON_FAILURE policy retries.
set -eu

SERVER_URL="${INFISICAL_INTERNAL_URL:?INFISICAL_INTERNAL_URL is required}"
ADMIN_EMAIL="${INFISICAL_ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${INFISICAL_ADMIN_PASSWORD:-}"
ORGANIZATION="${INFISICAL_ORGANIZATION_NAME:-Default Organization}"
WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-1200}"
POLL_SECONDS=5
MIN_PASSWORD_LENGTH=16

umask 077
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

log() { printf '[infisical-bootstrap] %s\n' "$*"; }
fail() { printf '[infisical-bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

if [ -z "$ADMIN_EMAIL" ]; then
  log "INFISICAL_ADMIN_EMAIL is empty: skipping. The first visitor to the site will create the admin account."
  exit 0
fi

# --- input validation -------------------------------------------------------
case "$SERVER_URL" in
  http://*|https://*) ;;
  *) fail "INFISICAL_INTERNAL_URL must start with http:// or https://" ;;
esac
SERVER_URL="${SERVER_URL%/}"

case "$ADMIN_EMAIL" in
  *[!A-Za-z0-9@._+-]*|*@*@*|@*|*@) fail "INFISICAL_ADMIN_EMAIL is not a plain e-mail address" ;;
  *@*.*) ;;
  *) fail "INFISICAL_ADMIN_EMAIL is not a plain e-mail address" ;;
esac

# Letters and digits only: matches the generated secret and keeps the JSON body safe.
case "$ADMIN_PASSWORD" in
  ''|*[!A-Za-z0-9]*) fail "INFISICAL_ADMIN_PASSWORD must contain only letters and digits" ;;
esac
[ "${#ADMIN_PASSWORD}" -ge "$MIN_PASSWORD_LENGTH" ] \
  || fail "INFISICAL_ADMIN_PASSWORD must be at least $MIN_PASSWORD_LENGTH characters"

case "$WAIT_SECONDS" in
  ''|*[!0-9]*) fail "BOOTSTRAP_WAIT_SECONDS must be a whole number" ;;
esac

# Escape backslashes and double quotes for the JSON string; drop control characters.
json_escape() { printf '%s' "$1" | tr -d '\001-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
ORGANIZATION="$(json_escape "$ORGANIZATION")"
[ -n "$ORGANIZATION" ] || ORGANIZATION="Default Organization"

# --- wait for the server ----------------------------------------------------
log "Waiting up to ${WAIT_SECONDS}s for Infisical at $SERVER_URL"
deadline=$(( $(date +%s) + WAIT_SECONDS ))
until curl -fsS --max-time 5 -o /dev/null "$SERVER_URL/api/status" 2>/dev/null; do
  [ "$(date +%s)" -lt "$deadline" ] || fail "Infisical did not answer within ${WAIT_SECONDS}s"
  sleep "$POLL_SECONDS"
done
log "Infisical is up"

# --- bootstrap ---------------------------------------------------------------
printf '{"email":"%s","password":"%s","organization":"%s"}' \
  "$ADMIN_EMAIL" "$ADMIN_PASSWORD" "$ORGANIZATION" > "$WORK_DIR/body.json"
status="$(curl -sS --max-time 60 -o "$WORK_DIR/out" -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  --data-binary "@$WORK_DIR/body.json" \
  "$SERVER_URL/api/v1/admin/bootstrap")" || fail "Bootstrap request failed"

case "$status" in
  200)
    log "Instance bootstrapped: super-admin $ADMIN_EMAIL, organization created."
    log "Sign in with the password stored in this service's INFISICAL_ADMIN_PASSWORD variable."
    ;;
  400)
    if grep -q 'already been set up' "$WORK_DIR/out"; then
      log "Instance has already been set up; nothing to do."
    else
      fail "HTTP 400 from /api/v1/admin/bootstrap: $(head -c 300 "$WORK_DIR/out")"
    fi
    ;;
  *)
    fail "HTTP $status from /api/v1/admin/bootstrap: $(head -c 300 "$WORK_DIR/out")"
    ;;
esac
