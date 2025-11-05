#!/usr/bin/env bash
set -euo pipefail

: "${EC2_HOST:?EC2_HOST is required}"
: "${REMOTE_DIR:?REMOTE_DIR is required}"
: "${COMPOSE_FILE:?COMPOSE_FILE is required}"
: "${GIT_REPO:?GIT_REPO is required}"
: "${ENV_FILE_PATH:?ENV_FILE_PATH is required}"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

command -v ssh >/dev/null 2>&1 || { echo "ssh command not available" >&2; exit 1; }
command -v scp >/dev/null 2>&1 || { echo "scp command not available" >&2; exit 1; }

echo "==> Ensuring project directory and repository on remote host"
ssh "${SSH_OPTS[@]}" "${EC2_HOST}" "REMOTE_DIR='${REMOTE_DIR}' GIT_REPO='${GIT_REPO}' bash -s" <<'REMOTE_SH'
set -euo pipefail
mkdir -p "$REMOTE_DIR"
if [ ! -d "$REMOTE_DIR/.git" ]; then
  git clone --depth 1 "$GIT_REPO" "$REMOTE_DIR"
else
  cd "$REMOTE_DIR"
  git fetch origin
  git reset --hard origin/main
fi
REMOTE_SH

echo "==> Uploading environment file"
scp "${SSH_OPTS[@]}" "${ENV_FILE_PATH}" "${EC2_HOST}:${REMOTE_DIR}/.env.production"

echo "==> Applying docker compose stack"
ssh "${SSH_OPTS[@]}" "${EC2_HOST}" "REMOTE_DIR='${REMOTE_DIR}' COMPOSE_FILE='${COMPOSE_FILE}' bash -s" <<'REMOTE_SH'
set -euo pipefail
cd "$REMOTE_DIR"
docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans
docker compose -f "$COMPOSE_FILE" ps
REMOTE_SH

echo "==> Deployment complete"
