#!/usr/bin/env bash
# Refresh the relay model list and switch the active model for
# Codex CLI and/or Claude Code on Linux/macOS.
#
# Reads the existing managed configuration written by the relay installers:
#   - Codex      : $CODEX_HOME/config.toml or ~/.codex/config.toml
#   - Claude Code: ~/.claude/settings.json
#
# Re-fetches /v1/models from the relay with the saved API key, lets you
# pick a new model, and rewrites only the model fields. Base URLs, API
# keys, and unrelated settings are left as-is. A timestamped backup is
# created before each file is changed.
#
# Usage:
#   update-relay-model-linux-macos.sh [options]
#
# Options:
#   --tool codex|claude|both    Which tool to update (default: auto)
#   --mode refresh|list|switch  refresh caches, list models, or switch default model (default: refresh)
#   --model NAME                Use this model without prompting
#   --base-url URL              Override base URL
#   --api-key KEY               Override API key (default: read from config)
#   --provider-id ID            Codex provider id (default: from config or "custom-relay")
#   --timeout SECONDS           HTTP timeout (default: 30)
#   --dry-run                   Show what would change without writing
#   --list-models               Print the model list and exit
#   --no-picker                 Skip interactive picker; keep current model
#   -h, --help                  Print this help and exit

set -euo pipefail

# Codex constants
CODEX_BEGIN_MARKER="# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK"
CODEX_END_MARKER="# END CODEX RELAY INSTALLER MANAGED BLOCK"
CODEX_DEFAULT_BASE_URL="https://litellm.blackwhitedeer.studio/v1"
CODEX_DEFAULT_PROVIDER_ID="custom-relay"

# Claude constants
CLAUDE_DEFAULT_BASE_URL="https://litellm.blackwhitedeer.studio"
CLAUDE_MODEL_ENV_KEYS=(
  ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL
)
CLAUDE_FAMILY_MODEL_ENV_KEYS=(
  ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL
)
CLAUDE_MODEL_DISCOVERY_ENV_KEY="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"

# Shared
FALLBACK_MODEL="gpt-5.5"
REQUEST_TIMEOUT_SEC=30

# Options
TOOL_OPT="auto"
MODE_OPT="refresh"
MODEL_OPT=""
BASE_URL_OPT=""
API_KEY_OPT=""
PROVIDER_ID_OPT=""
DRY_RUN=0
LIST_MODELS=0
NO_PICKER=0

#----------------------------------------------------------------------
# Logging
#----------------------------------------------------------------------
log() {
  local tag="${2:-relay}"
  printf '[%s] %s\n' "$tag" "$1" >&2
}

warn() {
  local tag="${2:-relay}"
  printf '[%s] %s\n' "$tag" "$1" >&2
}

die() {
  warn "$1" "${2:-relay}"
  exit 1
}

#----------------------------------------------------------------------
# Argument parsing
#----------------------------------------------------------------------
print_help() {
  # Print the leading comment block (everything up to the first non-comment line).
  awk '
    NR == 1 && /^#!/ { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    /^$/ { print; next }
    { exit }
  ' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tool)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--tool requires a value"
      TOOL_OPT="${2:-}"; shift 2 ;;
    --tool=*)
      TOOL_OPT="${1#--tool=}"; shift ;;
    --mode)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--mode requires a value"
      MODE_OPT="${2:-}"; shift 2 ;;
    --mode=*)
      MODE_OPT="${1#--mode=}"; shift ;;
    --model)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--model requires a value"
      MODEL_OPT="${2:-}"; shift 2 ;;
    --model=*)
      MODEL_OPT="${1#--model=}"; shift ;;
    --base-url)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--base-url requires a value"
      BASE_URL_OPT="${2:-}"; shift 2 ;;
    --base-url=*)
      BASE_URL_OPT="${1#--base-url=}"; shift ;;
    --api-key)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--api-key requires a value"
      API_KEY_OPT="${2:-}"; shift 2 ;;
    --api-key=*)
      API_KEY_OPT="${1#--api-key=}"; shift ;;
    --provider-id)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--provider-id requires a value"
      PROVIDER_ID_OPT="${2:-}"; shift 2 ;;
    --provider-id=*)
      PROVIDER_ID_OPT="${1#--provider-id=}"; shift ;;
    --timeout)
      [ $# -ge 2 ] && [ -n "${2:-}" ] || die "--timeout requires a value"
      REQUEST_TIMEOUT_SEC="${2:-30}"; shift 2 ;;
    --timeout=*)
      REQUEST_TIMEOUT_SEC="${1#--timeout=}"; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --list-models)
      LIST_MODELS=1; shift ;;
    --no-picker)
      NO_PICKER=1; shift ;;
    -h|--help)
      print_help; exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

case "$TOOL_OPT" in
  auto|codex|claude|both) ;;
  *) die "--tool must be one of: auto, codex, claude, both (got: $TOOL_OPT)" ;;
esac

case "$MODE_OPT" in
  refresh|list|switch) ;;
  *) die "--mode must be one of: refresh, list, switch (got: $MODE_OPT)" ;;
esac

resolve_run_mode() {
  if [ "$LIST_MODELS" -eq 1 ]; then
    printf 'list'
  elif [ -n "$MODEL_OPT" ]; then
    printf 'switch'
  elif [ "$NO_PICKER" -eq 1 ]; then
    printf 'refresh'
  else
    printf '%s' "$MODE_OPT"
  fi
}

RUN_MODE="$(resolve_run_mode)"

#----------------------------------------------------------------------
# Shared helpers
#----------------------------------------------------------------------
read_api_key_interactive() {
  local tag="${1:-relay}"
  local key=""
  if [ ! -t 0 ]; then
    die "No API key found in config and stdin is not a terminal; re-run interactively or pass --api-key." "$tag"
  fi
  local attempts=0
  while [ "$attempts" -lt 5 ]; do
    attempts=$((attempts + 1))
    printf '[%s] Paste your relay API key: ' "$tag" >&2
    if ! IFS= read -rs key; then
      printf '\n' >&2
      die "Stdin closed while reading API key." "$tag"
    fi
    printf '\n' >&2
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    if [ -n "$key" ]; then
      printf '%s' "$key"
      return 0
    fi
    warn "API key cannot be empty." "$tag"
  done
  die "Too many empty API key attempts; aborting." "$tag"
}

show_model_choices() {
  local models="$1"
  local tag="${2:-relay}"
  local total width
  total="$(printf '%s\n' "$models" | sed '/^$/d' | wc -l | tr -d ' ')"
  width="${#total}"
  [ "${width:-0}" -ge 3 ] || width=3
  printf '%s\n' "$models" | sed '/^$/d' | awk -v width="$width" '{ printf "  %*d. %s\n", width, NR, $0 }'
}

select_model() {
  local models="$1"
  local current="${2:-}"
  local tag="${3:-relay}"
  local total default index selected answer

  total="$(printf '%s\n' "$models" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "${total:-0}" -eq 0 ]; then
    die "Relay returned no models. Cannot pick a new model." "$tag"
  fi

  default=""
  if [ -n "$current" ] && printf '%s\n' "$models" | grep -Fxq -- "$current"; then
    default="$current"
  elif printf '%s\n' "$models" | grep -Fxq -- "$FALLBACK_MODEL"; then
    default="$FALLBACK_MODEL"
  else
    default="$(printf '%s\n' "$models" | sed -n '1p')"
  fi

  log "Available models from relay ($total total):" "$tag"
  show_model_choices "$models" "$tag"
  if [ -n "$current" ]; then
    log "Current model: $current" "$tag"
  fi

  while :; do
    printf '[%s] Choose default model number/name, or press Enter for %s: ' "$tag" "$default" >&2
    if ! IFS= read -r answer; then
      printf '%s' "$default"
      return 0
    fi
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"
    if [ -z "$answer" ]; then
      printf '%s' "$default"
      return 0
    fi
    if printf '%s' "$answer" | grep -Eq '^[0-9]+$'; then
      index="$answer"
      if [ "$index" -ge 1 ] && [ "$index" -le "$total" ]; then
        selected="$(printf '%s\n' "$models" | sed -n "${index}p")"
        printf '%s' "$selected"
        return 0
      fi
      warn "Model number out of range. Try again." "$tag"
      continue
    fi
    printf '%s' "$answer"
    return 0
  done
}

http_status_hint() {
  local status="$1"
  local tag="${2:-relay}"
  case "$status" in
    400) warn "HTTP 400: request was rejected. Check API compatibility." "$tag" ;;
    401) warn "HTTP 401: API key is missing or invalid." "$tag" ;;
    402) warn "HTTP 402: quota, balance, or payment limit may be exhausted." "$tag" ;;
    403) warn "HTTP 403: API key is valid but not allowed to use this resource." "$tag" ;;
    404) warn "HTTP 404: endpoint not found. Confirm the base URL." "$tag" ;;
    429) warn "HTTP 429: upstream rate limit or quota was reached." "$tag" ;;
    5*)  warn "HTTP $status: relay or upstream server error." "$tag" ;;
    *)   warn "HTTP $status: request failed." "$tag" ;;
  esac
}

fetch_models_ids() {
  # Fetches the model list JSON and prints one id per line.
  local url="$1"
  local api_key="$2"
  local tag="${3:-relay}"
  local body status

  command -v curl >/dev/null 2>&1 || die "curl was not found." "$tag"

  log "Fetching model list from: $url" "$tag"
  local tmp_body tmp_status
  tmp_body="$(mktemp)"
  tmp_status="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_body' '$tmp_status'" RETURN

  if ! curl -sS \
        --max-time "$REQUEST_TIMEOUT_SEC" \
        -o "$tmp_body" \
        -w '%{http_code}' \
        -H "Authorization: Bearer $api_key" \
        "$url" > "$tmp_status"; then
    warn "curl failed to fetch $url" "$tag"
    return 1
  fi

  status="$(cat "$tmp_status")"
  if [ "$status" != "200" ]; then
    http_status_hint "$status" "$tag"
    return 1
  fi

  body="$(cat "$tmp_body")"
  if [ -z "$body" ]; then
    warn "Relay returned an empty response." "$tag"
    return 1
  fi

  # Parse model IDs; prefer python, fall back to grep+sed.
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$body" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
seen = set()
for item in data.get("data", []) or []:
    mid = item.get("id") if isinstance(item, dict) else None
    if mid and mid not in seen:
        seen.add(mid)
        print(mid)
'
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$body" | python -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
seen = set()
for item in data.get("data", []) or []:
    mid = item.get("id") if isinstance(item, dict) else None
    if mid and mid not in seen:
        seen.add(mid)
        print(mid)
'
  else
    printf '%s' "$body" \
      | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | sed 's/.*"id"[[:space:]]*:[[:space:]]*"//; s/"$//' \
      | awk '!seen[$0]++'
  fi
}

backup_file() {
  local path="$1"
  local backup
  backup="${path}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$path" "$backup"
  printf '%s' "$backup"
}

#----------------------------------------------------------------------
# Codex helpers
#----------------------------------------------------------------------
codex_home() {
  if [ -n "${CODEX_HOME:-}" ]; then
    printf '%s' "$CODEX_HOME"
  else
    printf '%s/.codex' "$HOME"
  fi
}

codex_config_path() {
  printf '%s/config.toml' "$(codex_home)"
}

codex_model_cache_path() {
  printf '%s/models_cache.json' "$(codex_home)"
}

normalize_codex_base_url() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  while [ "${v: -1}" = "/" ]; do v="${v:0:-1}"; done
  printf '%s' "$v"
}

codex_join_url() {
  local base path
  base="$(normalize_codex_base_url "$1")"
  path="${2#/}"
  printf '%s/%s' "$base" "$path"
}

# Reads a top-level "key = "value"" string from a TOML file (first match only).
codex_get_toml_value() {
  local file="$1"
  local key="$2"
  awk -v k="$key" '
    /^[[:space:]]*\[/ { in_table = 1 }
    !in_table {
      n = match($0, "^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"")
      if (n > 0) {
        rest = substr($0, RSTART + RLENGTH)
        end = index(rest, "\"")
        if (end > 0) { print substr(rest, 1, end - 1); exit }
      }
    }
  ' "$file"
}

# Reads "key = "value"" from inside the [model_providers.PROVIDER] table.
codex_get_provider_value() {
  local file="$1"
  local provider="$2"
  local key="$3"
  awk -v header="[model_providers.${provider}]" -v quoted_header="[model_providers.\"${provider}\"]" -v k="$key" '
    {
      stripped = $0
      sub(/^[[:space:]]+/, "", stripped)
      sub(/[[:space:]]+$/, "", stripped)
    }
    stripped == header || stripped == quoted_header { in_block = 1; next }
    in_block && /^[[:space:]]*\[/ { in_block = 0 }
    in_block {
      n = match($0, "^[[:space:]]*" k "[[:space:]]*=[[:space:]]*\"")
      if (n > 0) {
        rest = substr($0, RSTART + RLENGTH)
        end = index(rest, "\"")
        if (end > 0) { print substr(rest, 1, end - 1); exit }
      }
    }
  ' "$file"
}

write_codex_model_cache() {
  local models="$1"
  local tag="${2:-codex-relay}"
  local cache_path cache_dir tmp_models py

  [ -n "$models" ] || return 0
  cache_path="$(codex_model_cache_path)"
  cache_dir="$(dirname "$cache_path")"
  mkdir -p "$cache_dir"
  tmp_models="$(mktemp)"
  printf '%s\n' "$models" | sed '/^$/d' > "$tmp_models"

  py="$(command -v python3 || command -v python || true)"
  if [ -n "$py" ]; then
    "$py" - "$tmp_models" "$cache_path" <<'PY' || rm -f "$cache_path"
import json
import sys
from datetime import datetime, timezone

models_path, cache_path = sys.argv[1:3]
seen = set()
entries = []
with open(models_path, "r", encoding="utf-8") as fh:
    for line in fh:
        model = line.strip()
        if not model or model in seen:
            continue
        seen.add(model)
        entries.append({
            "slug": model,
            "display_name": model,
            "id": "",
            "visibility": "list",
            "supported_in_api": True,
        })

payload = {
    "fetched_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "etag": None,
    "client_version": None,
    "models": entries,
}
with open(cache_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
  fi

  if [ ! -s "$cache_path" ]; then
    awk '
      function esc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        return s
      }
      BEGIN {
        print "{"
        print "  \"fetched_at\": \"\","
        print "  \"etag\": null,"
        print "  \"client_version\": null,"
        print "  \"models\": ["
      }
      NF && !seen[$0]++ {
        if (count++) print ","
        m = esc($0)
        printf "    {\"slug\":\"%s\",\"display_name\":\"%s\",\"id\":\"\",\"visibility\":\"list\",\"supported_in_api\":true}", m, m
      }
      END {
        print ""
        print "  ]"
        print "}"
      }
    ' "$tmp_models" > "$cache_path"
  fi

  rm -f "$tmp_models"
  if [ ! -s "$cache_path" ]; then
    warn "Failed to refresh model cache at $cache_path" "$tag"
    return 1
  fi
  log "Model cache refreshed: $cache_path" "$tag"
}

# Rewrites the "model = "..."" line inside the managed block at the top.
codex_replace_managed_model() {
  local file="$1"
  local model="$2"
  local tag="${3:-codex-relay}"

  # Escape model for sed replacement.
  local escaped
  escaped="$(printf '%s' "$model" | sed -e 's/[\/&]/\\&/g')"

  python3 - "$file" "$model" "$CODEX_BEGIN_MARKER" "$CODEX_END_MARKER" <<'PY' 2>/dev/null || return 1
import re, sys

path, model, begin_marker, end_marker = sys.argv[1:5]
with open(path, "r", encoding="utf-8-sig") as f:
    content = f.read()

pattern = re.compile(
    r"(^" + re.escape(begin_marker) + r"\s*$)(.*?)(^" + re.escape(end_marker) + r"\s*$)",
    re.MULTILINE | re.DOTALL,
)
m = pattern.search(content)
if not m:
    sys.exit(2)

body = m.group(2)
escaped_model = model.replace("\\", "\\\\").replace('"', '\\"')
new_body, count = re.subn(
    r'(?m)^(\s*model\s*=\s*)"[^"]*"',
    lambda mm: mm.group(1) + '"' + escaped_model + '"',
    body,
)
if count == 0:
    # Insert a model line at the top of the managed block body.
    new_body = "\nmodel = \"" + escaped_model + "\"" + body

new_content = content[: m.start()] + m.group(1) + new_body + m.group(3) + content[m.end():]
with open(path, "w", encoding="utf-8") as f:
    f.write(new_content)
PY
}

# Pure-shell fallback if python is unavailable. Uses awk to splice the block.
codex_replace_managed_model_awk() {
  local file="$1"
  local model="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v begin="$CODEX_BEGIN_MARKER" -v end="$CODEX_END_MARKER" -v model="$model" '
    BEGIN { in_block = 0; replaced = 0; found_block = 0 }
    {
      line = $0
      if (line == begin) {
        in_block = 1
        found_block = 1
        print line
        next
      }
      if (line == end) {
        if (in_block && !replaced) {
          print "model = \"" model "\""
        }
        in_block = 0
        print line
        next
      }
      if (in_block) {
        if (match(line, /^[[:space:]]*model[[:space:]]*=[[:space:]]*"[^"]*"/)) {
          print "model = \"" model "\""
          replaced = 1
          next
        }
      }
      print line
    }
    END {
      if (!found_block) exit 2
    }
  ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }

  mv "$tmp" "$file"
}

invoke_codex_update() {
  local tag="codex-relay"
  local config_path
  config_path="$(codex_config_path)"

  if [ ! -f "$config_path" ]; then
    warn "Codex relay config not found at $config_path. Skipping." "$tag"
    return 0
  fi

  local provider_id base_url api_key current_model
  current_model="$(codex_get_toml_value "$config_path" "model" || true)"
  provider_id="${PROVIDER_ID_OPT:-$(codex_get_toml_value "$config_path" "model_provider" || true)}"
  [ -n "$provider_id" ] || provider_id="$CODEX_DEFAULT_PROVIDER_ID"

  base_url="${BASE_URL_OPT:-$(codex_get_provider_value "$config_path" "$provider_id" "base_url" || true)}"
  [ -n "$base_url" ] || base_url="$CODEX_DEFAULT_BASE_URL"
  base_url="$(normalize_codex_base_url "$base_url")"

  api_key="${API_KEY_OPT:-$(codex_get_provider_value "$config_path" "$provider_id" "experimental_bearer_token" || true)}"
  if [ -z "$api_key" ]; then
    warn "No relay API key found in $config_path. You will be prompted." "$tag"
    api_key="$(read_api_key_interactive "$tag")"
  fi

  log "Config: $config_path" "$tag"
  log "Provider: $provider_id" "$tag"
  log "Base URL: $base_url" "$tag"
  [ -z "$current_model" ] || log "Currently configured model: $current_model" "$tag"

  local url models
  url="$(codex_join_url "$base_url" "models")"
  if ! models="$(fetch_models_ids "$url" "$api_key" "$tag")"; then
    warn "Failed to fetch /models. Skipping Codex update." "$tag"
    return 0
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    write_codex_model_cache "$models" "$tag"
  else
    log "Dry run: would refresh model cache: $(codex_model_cache_path)" "$tag"
  fi

  if [ "$RUN_MODE" = "list" ]; then
    if [ -z "$models" ]; then
      warn "Relay returned no models." "$tag"
      return 0
    fi
    show_model_choices "$models" "$tag"
    return 0
  fi

  if [ "$RUN_MODE" = "refresh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "Dry run: model list fetched; default model would remain unchanged." "$tag"
    else
      log "Model list refreshed. Current default model unchanged: ${current_model:-<unset>}" "$tag"
    fi
    return 0
  fi

  local resolved_model
  if [ -n "$MODEL_OPT" ]; then
    resolved_model="$MODEL_OPT"
    if [ -n "$models" ] && ! printf '%s\n' "$models" | grep -Fxq -- "$resolved_model"; then
      warn "Model '$resolved_model' is not in the relay /models response. Writing it anyway." "$tag"
    fi
  elif [ "$NO_PICKER" -eq 1 ]; then
    resolved_model="${current_model:-$FALLBACK_MODEL}"
    log "Skipping interactive picker. Keeping model: $resolved_model" "$tag"
  else
    resolved_model="$(select_model "$models" "$current_model" "$tag")"
  fi

  if [ "$resolved_model" = "$current_model" ]; then
    log "Selected model matches the current model ($resolved_model). Nothing to update." "$tag"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run: would update model -> $resolved_model in $config_path" "$tag"
    return 0
  fi

  local backup
  backup="$(backup_file "$config_path")"
  log "Backup written: $backup" "$tag"

  local rc=0
  if command -v python3 >/dev/null 2>&1; then
    codex_replace_managed_model "$config_path" "$resolved_model" "$tag" || rc=$?
  else
    rc=99
  fi
  if [ "$rc" -ne 0 ]; then
    if ! codex_replace_managed_model_awk "$config_path" "$resolved_model"; then
      warn "Could not find the managed block in $config_path. Re-run install-codex-relay-linux-macos.sh to rewrite the config." "$tag"
      mv "$backup" "$config_path"
      return 0
    fi
  fi

  log "Model updated to: $resolved_model" "$tag"
}

#----------------------------------------------------------------------
# Claude helpers
#----------------------------------------------------------------------
claude_home() {
  printf '%s/.claude' "$HOME"
}

claude_settings_path() {
  printf '%s/settings.json' "$(claude_home)"
}

claude_gateway_cache_path() {
  printf '%s/cache/gateway-models.json' "$(claude_home)"
}

normalize_claude_base_url() {
  local v="${1:-}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  if [ -z "$v" ]; then
    printf '%s' "$CLAUDE_DEFAULT_BASE_URL"
    return 0
  fi
  while [ "${v: -1}" = "/" ]; do v="${v:0:-1}"; done
  case "$v" in
    */v1/messages) v="${v%/v1/messages}" ;;
    */messages) v="${v%/messages}" ;;
    */v1) v="${v%/v1}" ;;
  esac
  while [ -n "$v" ] && [ "${v: -1}" = "/" ]; do v="${v:0:-1}"; done
  printf '%s' "$v"
}

claude_join_url() {
  local base path
  base="$(normalize_claude_base_url "$1")"
  path="${2#/}"
  printf '%s/v1/%s' "$base" "$path"
}

require_node() {
  command -v node >/dev/null 2>&1 || die "Node.js (node) is required to edit ~/.claude/settings.json. Install Node.js LTS and re-run." "claude-relay"
}

claude_get_env_value() {
  local key="$1"
  local path
  path="$(claude_settings_path)"
  [ -f "$path" ] || return 0
  node -e '
const fs = require("fs");
const path = process.argv[1];
const key = process.argv[2];
try {
  const data = JSON.parse(fs.readFileSync(path, "utf8"));
  const value = data.env && data.env[key];
  if (value) process.stdout.write(String(value));
} catch (_) {}
' "$path" "$key"
}

write_claude_model() {
  local model="$1"
  local sonnet_model="$2"
  local opus_model="$3"
  local haiku_model="$4"
  local path
  path="$(claude_settings_path)"
  SETTINGS_PATH="$path" \
  CLAUDE_RELAY_MODEL="$model" \
  CLAUDE_RELAY_SONNET_MODEL="$sonnet_model" \
  CLAUDE_RELAY_OPUS_MODEL="$opus_model" \
  CLAUDE_RELAY_HAIKU_MODEL="$haiku_model" \
  node <<'NODE'
const fs = require("fs");
const path = process.env.SETTINGS_PATH;
const model = process.env.CLAUDE_RELAY_MODEL;
let settings = {};
if (fs.existsSync(path)) {
  const raw = fs.readFileSync(path, "utf8").trim();
  if (raw) settings = JSON.parse(raw);
}
  if (!settings.env || typeof settings.env !== "object" || Array.isArray(settings.env)) {
    settings.env = {};
  }
settings.env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
settings.env.ANTHROPIC_MODEL = model;
settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL = process.env.CLAUDE_RELAY_SONNET_MODEL;
settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL = process.env.CLAUDE_RELAY_OPUS_MODEL;
settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = process.env.CLAUDE_RELAY_HAIKU_MODEL;
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
NODE
}

enable_claude_model_discovery() {
  local path
  path="$(claude_settings_path)"
  SETTINGS_PATH="$path" \
  CLAUDE_MODEL_DISCOVERY_ENV_KEY="$CLAUDE_MODEL_DISCOVERY_ENV_KEY" \
  node <<'NODE'
const fs = require("fs");
const path = process.env.SETTINGS_PATH;
const discoveryKey = process.env.CLAUDE_MODEL_DISCOVERY_ENV_KEY;
let settings = {};
if (fs.existsSync(path)) {
  const raw = fs.readFileSync(path, "utf8").trim();
  if (raw) settings = JSON.parse(raw);
}
if (!settings.env || typeof settings.env !== "object" || Array.isArray(settings.env)) {
  settings.env = {};
}
settings.env[discoveryKey] = "1";
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
NODE
}

write_claude_gateway_cache() {
  local models="$1"
  local base_url="$2"
  local tag="${3:-claude-relay}"
  local cache_path cache_dir tmp_models

  [ -n "$models" ] || return 0
  cache_path="$(claude_gateway_cache_path)"
  cache_dir="$(dirname "$cache_path")"
  mkdir -p "$cache_dir"
  tmp_models="$(mktemp)"
  printf '%s\n' "$models" | sed '/^$/d' > "$tmp_models"

  GATEWAY_MODELS_PATH="$tmp_models" \
  GATEWAY_CACHE_PATH="$cache_path" \
  GATEWAY_BASE_URL="$base_url" \
  node <<'NODE'
const fs = require("fs");
const modelsPath = process.env.GATEWAY_MODELS_PATH;
const cachePath = process.env.GATEWAY_CACHE_PATH;
const baseUrl = process.env.GATEWAY_BASE_URL;
const seen = new Set();
const models = [];
for (const line of fs.readFileSync(modelsPath, "utf8").split(/\r?\n/)) {
  const id = line.trim();
  if (!id || seen.has(id)) continue;
  seen.add(id);
  models.push({ id });
}
const payload = {
  baseUrl,
  fetchedAt: Date.now(),
  models,
};
fs.writeFileSync(cachePath, JSON.stringify(payload, null, 2) + "\n");
NODE

  rm -f "$tmp_models"
  log "Gateway cache refreshed: $cache_path" "$tag"
}

select_claude_family_model() {
  local models="$1"
  local family="$2"
  local current="${3:-}"
  local fallback="$4"

  if [ -n "$current" ] \
    && printf '%s\n' "$models" | grep -Fxq -- "$current" \
    && printf '%s' "$current" | grep -Eiq "$family"; then
    printf '%s' "$current"
    return 0
  fi

  local matched
  matched="$(printf '%s\n' "$models" | grep -Ei "$family" | sed -n '1p')"
  if [ -n "$matched" ]; then
    printf '%s' "$matched"
  else
    printf '%s' "$fallback"
  fi
}

invoke_claude_update() {
  local tag="claude-relay"
  local settings_path
  settings_path="$(claude_settings_path)"

  if [ ! -f "$settings_path" ]; then
    warn "Claude Code relay config not found at $settings_path. Skipping." "$tag"
    return 0
  fi

  require_node

  local base_url api_key current_model current_discovery current_sonnet current_opus current_haiku
  current_model="$(claude_get_env_value "ANTHROPIC_MODEL" || true)"
  current_discovery="$(claude_get_env_value "$CLAUDE_MODEL_DISCOVERY_ENV_KEY" || true)"
  current_sonnet="$(claude_get_env_value "ANTHROPIC_DEFAULT_SONNET_MODEL" || true)"
  current_opus="$(claude_get_env_value "ANTHROPIC_DEFAULT_OPUS_MODEL" || true)"
  current_haiku="$(claude_get_env_value "ANTHROPIC_DEFAULT_HAIKU_MODEL" || true)"
  base_url="${BASE_URL_OPT:-$(claude_get_env_value "ANTHROPIC_BASE_URL" || true)}"
  base_url="$(normalize_claude_base_url "$base_url")"

  api_key="${API_KEY_OPT:-$(claude_get_env_value "ANTHROPIC_AUTH_TOKEN" || true)}"
  if [ -z "$api_key" ]; then
    warn "No relay API key found in $settings_path. You will be prompted." "$tag"
    api_key="$(read_api_key_interactive "$tag")"
  fi

  log "Settings: $settings_path" "$tag"
  log "Base URL: $base_url" "$tag"
  [ -z "$current_model" ] || log "Currently configured model: $current_model" "$tag"

  local url models
  url="$(claude_join_url "$base_url" "models")"
  if ! models="$(fetch_models_ids "$url" "$api_key" "$tag")"; then
    warn "Failed to fetch /v1/models. Skipping Claude update." "$tag"
    return 0
  fi

  if [ "$RUN_MODE" = "list" ]; then
    if [ -z "$models" ]; then
      warn "Relay returned no models." "$tag"
      return 0
    fi
    if [ "$DRY_RUN" -eq 0 ]; then
      write_claude_gateway_cache "$models" "$base_url" "$tag"
    else
      log "Dry run: would refresh gateway model cache: $(claude_gateway_cache_path)" "$tag"
    fi
    show_model_choices "$models" "$tag"
    return 0
  fi

  if [ "$RUN_MODE" = "refresh" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      log "Dry run: would refresh gateway model cache: $(claude_gateway_cache_path)" "$tag"
      if [ "$current_discovery" != "1" ]; then
        log "Dry run: would enable model discovery in $settings_path" "$tag"
      fi
      return 0
    fi

    if [ "$current_discovery" != "1" ]; then
      local backup
      backup="$(backup_file "$settings_path")"
      log "Backup written: $backup" "$tag"
      enable_claude_model_discovery
      log "Model discovery enabled: $CLAUDE_MODEL_DISCOVERY_ENV_KEY=1" "$tag"
    fi
    write_claude_gateway_cache "$models" "$base_url" "$tag"
    log "Model list refreshed. Current default model unchanged: ${current_model:-<unset>}" "$tag"
    return 0
  fi

  local resolved_model
  if [ -n "$MODEL_OPT" ]; then
    resolved_model="$MODEL_OPT"
    if [ -n "$models" ] && ! printf '%s\n' "$models" | grep -Fxq -- "$resolved_model"; then
      warn "Model '$resolved_model' is not in the relay /v1/models response. Writing it anyway." "$tag"
    fi
  elif [ "$NO_PICKER" -eq 1 ]; then
    resolved_model="${current_model:-$FALLBACK_MODEL}"
    log "Skipping interactive picker. Keeping model: $resolved_model" "$tag"
  else
    resolved_model="$(select_model "$models" "$current_model" "$tag")"
  fi

  local sonnet_model opus_model haiku_model
  sonnet_model="$(select_claude_family_model "$models" "sonnet" "$current_sonnet" "$resolved_model")"
  opus_model="$(select_claude_family_model "$models" "opus" "$current_opus" "$resolved_model")"
  haiku_model="$(select_claude_family_model "$models" "haiku" "$current_haiku" "$resolved_model")"
  log "Resolved Claude default family models:" "$tag"
  log "  ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnet_model" "$tag"
  log "  ANTHROPIC_DEFAULT_OPUS_MODEL = $opus_model" "$tag"
  log "  ANTHROPIC_DEFAULT_HAIKU_MODEL = $haiku_model" "$tag"

  if [ "$DRY_RUN" -eq 0 ]; then
    write_claude_gateway_cache "$models" "$base_url" "$tag"
  else
    log "Dry run: would refresh gateway model cache: $(claude_gateway_cache_path)" "$tag"
  fi

  if [ "$resolved_model" = "$current_model" ] \
    && [ "$current_discovery" = "1" ] \
    && [ "$sonnet_model" = "$current_sonnet" ] \
    && [ "$opus_model" = "$current_opus" ] \
    && [ "$haiku_model" = "$current_haiku" ]; then
    log "Selected model matches the current model ($resolved_model). Nothing to update." "$tag"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run: would enable model discovery and update Claude Code default/family models in $settings_path" "$tag"
    return 0
  fi

  local backup
  backup="$(backup_file "$settings_path")"
  log "Backup written: $backup" "$tag"
  write_claude_model "$resolved_model" "$sonnet_model" "$opus_model" "$haiku_model"
  log "Default model updated to: $resolved_model" "$tag"
  log "Model discovery enabled: $CLAUDE_MODEL_DISCOVERY_ENV_KEY=1" "$tag"
  log "Updated default/family model env keys: $(printf '%s, ' "${CLAUDE_MODEL_ENV_KEYS[@]}" | sed 's/, $//')" "$tag"
}

#----------------------------------------------------------------------
# Tool selection
#----------------------------------------------------------------------
resolve_tool_selection() {
  local codex_exists=0
  local claude_exists=0
  [ -f "$(codex_config_path)" ] && codex_exists=1
  [ -f "$(claude_settings_path)" ] && claude_exists=1

  if [ "$TOOL_OPT" != "auto" ]; then
    case "$TOOL_OPT" in
      codex)
        [ "$codex_exists" -eq 1 ] || warn "Codex config not found at $(codex_config_path). Run install-codex-relay-linux-macos.sh first." ;;
      claude)
        [ "$claude_exists" -eq 1 ] || warn "Claude config not found at $(claude_settings_path). Run install-claude-code-relay-linux-macos.sh first." ;;
      both)
        [ "$codex_exists" -eq 1 ] || warn "Codex config not found at $(codex_config_path). It will be skipped."
        [ "$claude_exists" -eq 1 ] || warn "Claude config not found at $(claude_settings_path). It will be skipped." ;;
    esac
    printf '%s' "$TOOL_OPT"
    return 0
  fi

  if [ "$codex_exists" -eq 1 ] && [ "$claude_exists" -eq 1 ]; then
    log "Detected both Codex ($(codex_config_path)) and Claude Code ($(claude_settings_path))."
    local answer
    while :; do
      printf '[relay] Update which tool? [1] Codex  [2] Claude Code  [3] both (default 3): ' >&2
      if ! IFS= read -r answer; then
        printf 'both'
        return 0
      fi
      answer="${answer#"${answer%%[![:space:]]*}"}"
      answer="${answer%"${answer##*[![:space:]]}"}"
      case "$answer" in
        ""|"3"|"both") printf 'both'; return 0 ;;
        "1"|"codex") printf 'codex'; return 0 ;;
        "2"|"claude") printf 'claude'; return 0 ;;
        *) warn "Pick 1, 2, or 3." ;;
      esac
    done
  fi
  if [ "$codex_exists" -eq 1 ]; then
    log "Auto-detected Codex relay config."
    printf 'codex'
    return 0
  fi
  if [ "$claude_exists" -eq 1 ]; then
    log "Auto-detected Claude Code relay config."
    printf 'claude'
    return 0
  fi
  die "Neither $(codex_config_path) nor $(claude_settings_path) was found. Run one of the install scripts first."
}

resolved_tool="$(resolve_tool_selection)"

case "$resolved_tool" in
  codex)  invoke_codex_update ;;
  claude) invoke_claude_update ;;
  both)   invoke_codex_update; invoke_claude_update ;;
esac
