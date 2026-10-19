# Invoked by the Home Manager hindsight-server wrapper; never enable shell tracing.
set -euo pipefail
umask 077
image='ghcr.io/vectorize-io/hindsight-api:0.8.6@sha256:3db1536d84a14a10afbd08cc8f82bf4eec03c123d950705226c999bea14ca0f0'
root="${HINDSIGHT_DATA_DIR:-$HOME/.local/share/hindsight}"
auth_home="$HOME/.local/state/hindsight-codex"
token_file="$HOME/.config/hindsight/api-token"
runtime="${XDG_RUNTIME_DIR:?}/hindsight"
name=hindsight-api

case "${1:-}" in
  start)
    test -s "$auth_home/auth.json" || { echo 'Dedicated Hindsight login is missing' >&2; exit 1; }
    test -s "$token_file" || { echo 'Hindsight API token is missing' >&2; exit 1; }
    install -d -m 0700 "$root" "$root/pg0" "$root/cache" "$root/staging" "$root/backups" "$runtime"
    python3 - "$token_file" "$runtime/server.env" <<'PY'
import os, pathlib, re, sys
value = pathlib.Path(sys.argv[1]).read_text().strip()
if not re.fullmatch(r'hsk_[A-Za-z0-9_-]+', value):
    raise SystemExit('Invalid Hindsight API token format')
fd = os.open(sys.argv[2], os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'w') as stream:
    stream.write('HINDSIGHT_API_TENANT_API_KEY=' + value + '\n')
os.chmod(sys.argv[2], 0o600)
PY
    tail_ip=$(tailscale ip -4)
    test -n "$tail_ip"
    exec podman run --name "$name" --replace --rm --pull=missing \
      --userns=keep-id:uid=1000,gid=100 \
      --cap-drop=ALL --security-opt=no-new-privileges \
      --cpus=4 --memory=8g --shm-size=2g --pids-limit=512 \
      -p "127.0.0.1:8888:8888" -p "$tail_ip:8888:8888" \
      --env-file "$runtime/server.env" \
      -e CODEX_HOME=/home/hindsight/.codex \
      -e HINDSIGHT_API_MCP_ENABLED=false \
      -e HINDSIGHT_API_TENANT_EXTENSION=hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension \
      -e HINDSIGHT_API_LLM_PROVIDER=openai-codex \
      -e HINDSIGHT_API_LLM_MODEL=gpt-6-astra \
      -e HINDSIGHT_API_LLM_REASONING_EFFORT=low \
      -e HINDSIGHT_API_LLM_STRICT_SCHEMA=true \
      -e HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS=8192 \
      -e HINDSIGHT_API_EMBEDDINGS_PROVIDER=local \
      -e HINDSIGHT_API_EMBEDDINGS_LOCAL_MODEL=BAAI/bge-small-en-v1.5 \
      -e HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU=true \
      -e HINDSIGHT_API_RERANKER_PROVIDER=rrf \
      -e HINDSIGHT_API_WORKER_ENABLED="${HINDSIGHT_WORKER_ENABLED:-true}" \
      -e HINDSIGHT_API_WORKER_ID=oppy-hindsight \
      -e HINDSIGHT_API_WORKER_MAX_SLOTS=2 \
      -e HINDSIGHT_API_WORKER_RETAIN_RESERVED_SLOTS=1 \
      -e HINDSIGHT_API_WORKER_CONSOLIDATION_RESERVED_SLOTS=0 \
      -e HINDSIGHT_API_ENABLE_AUTO_CONSOLIDATION=false \
      -e OMP_NUM_THREADS=2 -e MKL_NUM_THREADS=2 -e TOKENIZERS_PARALLELISM=false \
      -v "$root/pg0:/home/hindsight/.pg0" \
      -v "$root/cache:/home/hindsight/.cache" \
      -v "$root/staging:/backups" \
      -v "$auth_home:/home/hindsight/.codex" \
      --health-cmd='python -c "import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8888/health\", timeout=3)"' \
      --health-interval=30s --health-timeout=5s --health-retries=5 \
      --health-start-period=300s --health-on-failure=kill \
      "$image"
    ;;
  ready)
    for _ in $(seq 1 180); do
      if curl -fsS --max-time 3 http://127.0.0.1:8888/health >/dev/null; then exit 0; fi
      sleep 3
    done
    echo 'Hindsight did not become healthy' >&2
    exit 1
    ;;
  stop)
    podman stop --ignore --time 30 "$name"
    ;;
  backup)
    install -d -m 0700 "$root/staging" "$root/backups"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    plain="$root/staging/hindsight-$stamp.zip"
    encrypted="$root/backups/hindsight-$stamp.zip.age"
    trap 'rm -f "$plain" "$encrypted.tmp"' EXIT
    podman exec "$name" hindsight-admin backup "/backups/hindsight-$stamp.zip"
    age -r 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4' \
      -o "$encrypted.tmp" "$plain"
    chmod 0600 "$encrypted.tmp"
    mv "$encrypted.tmp" "$encrypted"
    printf 'Encrypted Hindsight backup: %s\n' "$encrypted"
    ;;
  *) echo 'usage: hindsight-server {start|ready|stop|backup}' >&2; exit 2 ;;
esac
