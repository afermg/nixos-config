{
  config,
  lib,
  pkgs,
  ...
}:
let
  image = "ghcr.io/vectorize-io/hindsight-api:0.8.6@sha256:3db1536d84a14a10afbd08cc8f82bf4eec03c123d950705226c999bea14ca0f0";
  dataRoot = "/var/lib/hindsight";
  backupRoot = "/home/amunoz/.local/share/syncthing/hindsight-backups/moby";
  personalAgeRecipient = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAKdcdlNS1SO+rJHjRQWd33qvqBEZcZR8ypTQUeC9LZ4";
  mobyAgeRecipient = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIClOuXVukvwqgE+UDxJShus+JGprTC8QIoc1G/Ege5KK";
  healthCheck = pkgs.writeText "hindsight-healthcheck.py" ''
    import pathlib
    import time
    import urllib.request

    start = pathlib.Path("/tmp/hindsight-health-start")
    ready = pathlib.Path("/tmp/hindsight-health-ready")
    now = time.monotonic()
    try:
        started_at = float(start.read_text())
    except (FileNotFoundError, ValueError):
        start.write_text(str(now))
        started_at = now

    try:
        with urllib.request.urlopen("http://127.0.0.1:8888/health", timeout=3):
            pass
    except Exception:
        # Podman executes the first probe immediately. Keep its transient
        # systemd helper successful during the declared startup grace period;
        # ExecStartPost below independently gates service readiness.
        if ready.exists() or now - started_at >= 120:
            raise
    else:
        ready.touch()
  '';
  restoreTest = pkgs.writeShellApplication {
    name = "hindsight-restore-test";
    runtimeInputs = with pkgs; [
      age
      coreutils
      curl
      jq
      podman
    ];
    text = ''
      set -euo pipefail
      if [ "$#" -ne 3 ]; then
        echo "usage: hindsight-restore-test ARCHIVE.age BANK EXPECTED_MARKER" >&2
        exit 2
      fi
      if [ "$(id -u)" -ne 0 ]; then
        echo "hindsight-restore-test must run as root" >&2
        exit 2
      fi

      archive=$(realpath "$1")
      bank=$2
      marker=$3
      test_root=${dataRoot}/restore-test
      container=hindsight-restore-test
      cleanup() {
        podman rm -f "$container" >/dev/null 2>&1 || true
        rm -rf "$test_root"
      }
      trap cleanup EXIT
      podman rm -f "$container" >/dev/null 2>&1 || true
      rm -rf "$test_root"
      install -d -m 0700 "$test_root/pg0" "$test_root/cache"
      chown -R 1000:100 "$test_root"
      age -d -i /etc/ssh/ssh_host_ed25519_key -o "$test_root/backup.zip" "$archive"
      chown 1000:100 "$test_root/backup.zip"
      chmod 0600 "$test_root/backup.zip"

      podman run -d --name "$container" \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        -p 127.0.0.1:18888:8888 \
        --env-file /run/hindsight/server.env \
        -e HINDSIGHT_API_MCP_ENABLED=false \
        -e HINDSIGHT_API_TENANT_EXTENSION=hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension \
        -e HINDSIGHT_API_LLM_PROVIDER=none \
        -e HINDSIGHT_API_WORKER_ENABLED=false \
        -e HINDSIGHT_API_WORKER_ID=moby-hindsight-restore-test \
        -v "$test_root/pg0:/home/hindsight/.pg0" \
        -v "$test_root/cache:/home/hindsight/.cache" \
        -v "$test_root/backup.zip:/restore/backup.zip:ro" \
        ${lib.escapeShellArg image} >/dev/null

      for attempt in $(seq 1 180); do
        if curl -fsS http://127.0.0.1:18888/health >/dev/null; then
          break
        fi
        if [ "$attempt" -eq 180 ]; then
          echo "isolated restore API did not become ready" >&2
          exit 1
        fi
        sleep 1
      done

      podman exec "$container" hindsight-admin restore /restore/backup.zip --yes
      token=$(cat ${lib.escapeShellArg config.age.secrets.hindsight-api-token.path})
      encoded_bank=$(jq -rn --arg value "$bank" '$value|@uri')
      response=$(curl -fsS \
        -H "Authorization: Bearer $token" \
        -H 'Content-Type: application/json' \
        -d '{"query":"durable project configuration","max_tokens":1024,"budget":"mid","types":["world","experience"]}' \
        "http://127.0.0.1:18888/v1/default/banks/$encoded_bank/memories/recall")
      unset token
      if ! jq -r '.. | strings' <<<"$response" | grep -Fq -- "$marker"; then
        echo "restored marker was not recallable" >&2
        exit 1
      fi
      echo "isolated Hindsight restore verified"
    '';
  };
in
{
  environment.systemPackages = [ restoreTest ];

  virtualisation = {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers.hindsight-api = {
        inherit image;
        pull = "missing";
        autoStart = true;
        ports = [ "100.94.5.85:8888:8888" ];
        environmentFiles = [ "/run/hindsight/server.env" ];
        environment = {
          CODEX_HOME = "/home/hindsight/.codex";
          HINDSIGHT_API_MCP_ENABLED = "false";
          HINDSIGHT_API_TENANT_EXTENSION = "hindsight_api.extensions.builtin.tenant:ApiKeyTenantExtension";
          HINDSIGHT_API_LLM_PROVIDER = "openai-codex";
          HINDSIGHT_API_LLM_MODEL = "gpt-5.4-mini";
          HINDSIGHT_API_LLM_REASONING_EFFORT = "low";
          HINDSIGHT_API_LLM_STRICT_SCHEMA = "true";
          HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS = "8192";
          HINDSIGHT_API_CONSOLIDATION_MAX_COMPLETION_TOKENS = "8192";
          HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU = "true";
          HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU = "true";
          HINDSIGHT_API_WORKER_ID = "moby-hindsight";
          HINDSIGHT_API_WORKER_MAX_SLOTS = "2";
          HINDSIGHT_API_WORKER_RETAIN_RESERVED_SLOTS = "1";
          HINDSIGHT_API_WORKER_CONSOLIDATION_RESERVED_SLOTS = "0";
          HINDSIGHT_API_CONSOLIDATION_LLM_PARALLELISM = "1";
        };
        volumes = [
          "${dataRoot}/pg0:/home/hindsight/.pg0"
          "${dataRoot}/cache:/home/hindsight/.cache"
          "/home/amunoz/.local/state/hindsight-codex:/home/hindsight/.codex"
          "${dataRoot}/backup-staging:/backups"
          "${healthCheck}:/hindsight-healthcheck.py:ro"
        ];
        extraOptions = [
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--pids-limit=512"
          "--memory=24g"
          "--health-cmd=python /hindsight-healthcheck.py"
          "--health-interval=30s"
          "--health-timeout=5s"
          "--health-retries=5"
          "--health-start-period=120s"
          "--health-on-failure=kill"
        ];
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataRoot} 0700 amunoz users -"
    "d ${dataRoot}/pg0 0700 amunoz users -"
    "d ${dataRoot}/cache 0700 amunoz users -"
    "d /home/amunoz/.local/state/hindsight-codex 0700 amunoz users -"
    "d ${dataRoot}/backup-staging 0700 amunoz users -"
    "d /run/hindsight 0700 root root -"
    "d /home/amunoz/.local/share/syncthing/hindsight-backups 0700 amunoz users -"
    "d ${backupRoot} 0700 amunoz users -"
  ];

  systemd.services.podman-hindsight-api = {
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    requires = [ "tailscaled.service" ];
    preStart = lib.mkAfter ''
      set -eu
      ${pkgs.coreutils}/bin/install -d -m 0700 /run/hindsight
      token=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.age.secrets.hindsight-api-token.path})
      ${pkgs.coreutils}/bin/printf 'HINDSIGHT_API_TENANT_API_KEY=%s\n' "$token" > /run/hindsight/server.env
      unset token
      ${pkgs.coreutils}/bin/chmod 0600 /run/hindsight/server.env

      test -s /home/amunoz/.local/state/hindsight-codex/auth.json || {
        echo "Dedicated Hindsight Codex login is missing from /home/amunoz/.local/state/hindsight-codex/auth.json" >&2
        exit 1
      }

      for attempt in $(${pkgs.coreutils}/bin/seq 1 120); do
        if ${pkgs.iproute2}/bin/ip -4 address show dev tailscale0 | ${pkgs.gnugrep}/bin/grep -q '100\.94\.5\.85/'; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "Tailscale address 100.94.5.85 was not ready" >&2
      exit 1
    '';
    postStart = lib.mkAfter ''
      for attempt in $(${pkgs.coreutils}/bin/seq 1 180); do
        if ${pkgs.curl}/bin/curl -fsS --max-time 3 http://100.94.5.85:8888/health >/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo "Hindsight API did not become healthy" >&2
      exit 1
    '';
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "15s";
    };
  };

  systemd.services.hindsight-backup = {
    description = "Create an encrypted Hindsight backup for Syncthing";
    after = [ "podman-hindsight-api.service" ];
    requires = [ "podman-hindsight-api.service" ];
    path = [
      pkgs.age
      pkgs.coreutils
      pkgs.findutils
      pkgs.podman
    ];
    script = ''
      set -euo pipefail
      umask 077
      stamp=$(date -u +%Y%m%dT%H%M%SZ)
      plain="${dataRoot}/backup-staging/hindsight-$stamp.zip"
      encrypted="${backupRoot}/hindsight-$stamp.zip.age"
      temporary="$encrypted.tmp"
      cleanup() {
        rm -f "$plain" "$temporary"
      }
      trap cleanup EXIT

      podman exec hindsight-api hindsight-admin backup "/backups/hindsight-$stamp.zip"
      age \
        -r ${lib.escapeShellArg personalAgeRecipient} \
        -r ${lib.escapeShellArg mobyAgeRecipient} \
        -o "$temporary" \
        "$plain"
      chown amunoz:users "$temporary"
      chmod 0600 "$temporary"
      mv "$temporary" "$encrypted"

      # Retain roughly six months of weekly archives. Syncthing staggered
      # versioning independently protects remote deletions and replacements.
      find ${lib.escapeShellArg backupRoot} -maxdepth 1 -type f \
        -name 'hindsight-*.zip.age' -mtime +183 -delete
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.hindsight-backup = {
    description = "Weekly encrypted Hindsight backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:15:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
      Unit = "hindsight-backup.service";
    };
  };
}
