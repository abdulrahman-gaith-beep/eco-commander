#!/usr/bin/env bash
# DESC: Start local n8n via Docker when available, otherwise via npx
# INPUTS: none
# OUTPUT: running n8n on http://127.0.0.1:5678
# USES: Docker or Node.js/npx
# HUMAN: run the recipe; it picks the best local startup path
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  n8n-start.sh
  n8n-start.sh --help

Behavior:
  1. If Docker is installed and the daemon is reachable, start n8n with Docker.
  2. Otherwise, fall back to `npx n8n`.
  3. If neither path works, exit with a clear error.

Environment:
  ECO_N8N_COMPOSE          Optional explicit docker compose file to use
  ECO_N8N_COMPOSE_DEFAULT  Optional preferred compose file to try first
  N8N_CONTAINER_NAME   Docker container name (default: n8n)
  N8N_IMAGE            Docker image (default: docker.n8n.io/n8nio/n8n)
  N8N_VOLUME_NAME      Docker volume name (default: n8n_data)
  N8N_PORT             Host port for Docker mode (default: 5678)
EOF
}

say() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

pick_n8n_compose() {
  if [ -n "${ECO_N8N_COMPOSE:-}" ]; then
    [ -f "$ECO_N8N_COMPOSE" ] || die "ECO_N8N_COMPOSE does not exist: $ECO_N8N_COMPOSE"
    printf '%s\n' "$ECO_N8N_COMPOSE"
    return 0
  fi

  local roots=()
  [ -d "$HOME/projects" ] && roots+=("$HOME/projects")
  [ -d "$HOME/Projects" ] && roots+=("$HOME/Projects")

  if [ -n "${ECO_N8N_COMPOSE_DEFAULT:-}" ] && [ -f "$ECO_N8N_COMPOSE_DEFAULT" ]; then
    printf '%s\n' "$ECO_N8N_COMPOSE_DEFAULT"
    return 0
  fi

  local preferred
  for preferred in \
    "$HOME/projects/my-project/n8n/docker-compose.yml" \
    "$HOME/Projects/my-project/n8n/docker-compose.yml"; do
    if [ -f "$preferred" ]; then
      printf '%s\n' "$preferred"
      return 0
    fi
  done

  local root=""
  local compose=""
  for root in "${roots[@]}"; do
    compose="$(
      find "$root" -maxdepth 5 \
        \( -name 'docker-compose.yml' -o -name 'compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' \) \
        -print 2>/dev/null |
        while IFS= read -r file; do
          if grep -Eq '(^[[:space:]]*n8n:|image:[[:space:]]*(docker\.n8n\.io/)?n8nio/n8n)' "$file"; then
            printf '%s\n' "$file"
          fi
        done |
        head -n 1
    )"
    if [ -n "$compose" ]; then
      printf '%s\n' "$compose"
      return 0
    fi
  done

  return 1
}

start_with_docker() {
  local port="${N8N_PORT:-5678}"
  local container_name="${N8N_CONTAINER_NAME:-n8n}"
  local image="${N8N_IMAGE:-docker.n8n.io/n8nio/n8n}"
  local volume_name="${N8N_VOLUME_NAME:-n8n_data}"
  local compose=""

  if docker compose version >/dev/null 2>&1; then
    compose="$(pick_n8n_compose || true)"
    if [ -n "$compose" ]; then
      local compose_dir
      compose_dir="$(dirname "$compose")"
      say "Starting n8n via docker compose: $compose"
      (
        cd "$compose_dir"
        docker compose -f "$compose" up -d n8n
      )
      say "n8n should be available at http://127.0.0.1:${port}"
      return 0
    fi
  fi

  if docker ps --format '{{.Names}}' | grep -Fxq "$container_name"; then
    say "n8n Docker container '$container_name' is already running."
    say "n8n should be available at http://127.0.0.1:${port}"
    return 0
  fi

  if docker ps -a --format '{{.Names}}' | grep -Fxq "$container_name"; then
    say "Starting existing n8n Docker container '$container_name'..."
    docker start "$container_name" >/dev/null
    say "n8n should be available at http://127.0.0.1:${port}"
    return 0
  fi

  say "No existing n8n container found. Creating one from $image..."
  docker volume create "$volume_name" >/dev/null
  docker run -d \
    --name "$container_name" \
    -p "${port}:5678" \
    -v "${volume_name}:/home/node/.n8n" \
    "$image" >/dev/null
  say "n8n Docker container '$container_name' started."
  say "n8n should be available at http://127.0.0.1:${port}"
}

start_with_npx() {
  say "Docker is unavailable. Falling back to 'npx n8n'..."
  npx n8n
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    "")
      ;;
    *)
      usage >&2
      die "this recipe does not accept arguments"
      ;;
  esac

  if [ -n "${ECO_N8N_COMPOSE:-}" ] && [ ! -f "$ECO_N8N_COMPOSE" ]; then
    die "ECO_N8N_COMPOSE does not exist: $ECO_N8N_COMPOSE"
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
      start_with_docker
      exit 0
    fi
    say "Docker CLI is installed, but the daemon is not reachable."
  fi

  if command -v npx >/dev/null 2>&1; then
    if start_with_npx; then
      exit 0
    fi
    die "Docker is unavailable and 'npx n8n' failed. Ensure Node.js/npm can run n8n."
  fi

  die "Neither a usable Docker runtime nor 'npx' is available. Install Docker or Node.js/npm, then try again."
}

main "$@"
