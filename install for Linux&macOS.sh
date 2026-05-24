#!/usr/bin/env bash
set -euo pipefail

BEGIN_MARKER="# BEGIN CODEX RELAY INSTALLER MANAGED BLOCK"
END_MARKER="# END CODEX RELAY INSTALLER MANAGED BLOCK"
DEFAULT_BASE_URL="https://litellm.blackwhitedeer.studio/v1"
WINDOWS_SANDBOX_LINE='sandbox = "elevated"'

DRY_RUN=0
UNINSTALL=0
RESTORE=0
DOCTOR=0
TEST_CONNECTION=0
BENCHMARK=0
LIST_MODELS=0
NO_MODEL_PICKER=0
SKIP_CODEX_CHECK=0
PROVIDER_ID="custom-relay"
BASE_URL="$DEFAULT_BASE_URL"
MODEL=""
REQUEST_TIMEOUT_SEC=30

usage() {
  cat <<'EOF'
Usage: bash "install for Linux&macOS.sh" [options]

Configure Codex CLI, Codex Desktop, and the VS Code Codex extension to use an
OpenAI Responses-compatible relay.

Options:
  --dry-run                 Print planned config without writing files.
  --uninstall               Restore the latest config backup and remove env setup.
  --restore                 Restore the latest config backup only.
  --doctor                  Diagnose Codex, config, env var, and relay reachability.
  --test                    Send a minimal POST /v1/responses request.
  --benchmark               Run one-time speed and quota/status checks without writing config.
  --list-models             List models from GET /v1/models.
  --no-model-picker         Do not fetch models during install; use --model or default.
  --skip-codex-check        Do not check or offer to install Codex CLI.
  --provider-id VALUE       Provider id to write in config.toml. Default: custom-relay.
  --base-url VALUE          Relay base URL, include /v1 if your service uses it.
  --model VALUE             Default Codex model. Default: gpt-5.5.
  --timeout VALUE           HTTP timeout seconds. Default: 30.
  -h, --help                Show this help.
EOF
}

log() {
  printf '[codex-relay] %s\n' "$*"
}

warn() {
  printf '[codex-relay] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[codex-relay] ERROR: %s\n' "$*" >&2
  exit 1
}

script_path_for_help() {
  case "$0" in
    /*)
      printf '%s\n' "$0"
      ;;
    *)
      script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || true)"
      if [ -n "$script_dir" ]; then
        printf '%s/%s\n' "$script_dir" "$(basename "$0")"
      else
        printf '%s\n' "$0"
      fi
      ;;
  esac
}

print_rerun_hints() {
  script_path="$(script_path_for_help)"
  log "Use the full installer path for future local runs:"
  log "  bash \"$script_path\" --doctor"
  log "  bash \"$script_path\" --uninstall"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --restore)
      RESTORE=1
      shift
      ;;
    --doctor)
      DOCTOR=1
      shift
      ;;
    --test)
      TEST_CONNECTION=1
      shift
      ;;
    --benchmark)
      BENCHMARK=1
      shift
      ;;
    --list-models)
      LIST_MODELS=1
      shift
      ;;
    --no-model-picker)
      NO_MODEL_PICKER=1
      shift
      ;;
    --skip-codex-check)
      SKIP_CODEX_CHECK=1
      shift
      ;;
    --provider-id)
      PROVIDER_ID="${2:-}"
      shift 2
      ;;
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --timeout)
      REQUEST_TIMEOUT_SEC="${2:-30}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

mode_count=$((RESTORE + UNINSTALL + DOCTOR + TEST_CONNECTION + BENCHMARK + LIST_MODELS))
[ "$mode_count" -gt 1 ] && die "Use only one mode at a time: --restore, --uninstall, --doctor, --test, --benchmark, or --list-models."

codex_home() {
  if [ -n "${CODEX_HOME:-}" ]; then
    printf '%s\n' "$CODEX_HOME"
  else
    printf '%s\n' "$HOME/.codex"
  fi
}

config_path() {
  printf '%s/config.toml\n' "$(codex_home)"
}

assert_provider_id() {
  case "$PROVIDER_ID" in
    *[!A-Za-z0-9_-]*|'')
      die "Provider id may only contain letters, numbers, underscore, and dash."
      ;;
  esac
}

prompt_value() {
  prompt="$1"
  current="$2"
  if [ -n "$current" ]; then
    printf '%s\n' "$current"
    return
  fi

  while true; do
    if [ -r /dev/tty ]; then
      printf '%s: ' "$prompt" > /dev/tty
      IFS= read -r value < /dev/tty
    else
      printf '%s: ' "$prompt" >&2
      IFS= read -r value
    fi
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
    warn "Value cannot be empty."
  done
}

prompt_secret() {
  while true; do
    if [ -r /dev/tty ]; then
      printf 'Paste your relay API key: ' > /dev/tty
      stty -echo < /dev/tty
      IFS= read -r value < /dev/tty
      stty echo < /dev/tty
      printf '\n' > /dev/tty
    else
      printf 'Paste your relay API key: ' >&2
      IFS= read -r value
    fi
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
    warn "API key cannot be empty."
  done
}

toml_escape() {
  value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\r'/}
  value=${value//$'\n'/}
  printf '%s' "$value"
}

normalize_base_url() {
  value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  while [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  case "$value" in
    http://*|https://*) ;;
    *) warn "Base URL does not start with http:// or https://. Keeping it exactly as entered." ;;
  esac
  printf '%s\n' "$value"
}

join_api_url() {
  base="$(normalize_base_url "$1")"
  path="${2#/}"
  printf '%s/%s\n' "$base" "$path"
}

relay_root_url() {
  base="$(normalize_base_url "$1")"
  case "$base" in
    */v1) printf '%s\n' "${base%/v1}" ;;
    *) printf '%s\n' "$base" ;;
  esac
}

json_escape() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  elif command -v python >/dev/null 2>&1; then
    python -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  elif command -v node >/dev/null 2>&1; then
    node -e 'let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>process.stdout.write(JSON.stringify(s)));'
  else
    sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
  fi
}

parse_model_ids() {
  json_file="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$json_file" <<'PY'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    payload = json.load(f)
for item in payload.get("data", []):
    model_id = item.get("id")
    if model_id:
        print(model_id)
PY
  elif command -v python >/dev/null 2>&1; then
    python - "$json_file" <<'PY'
import json, sys
with open(sys.argv[1], "r") as f:
    payload = json.load(f)
for item in payload.get("data", []):
    model_id = item.get("id")
    if model_id:
        print(model_id)
PY
  elif command -v node >/dev/null 2>&1; then
    node - "$json_file" <<'JS'
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const item of payload.data || []) {
  if (item.id) console.log(item.id);
}
JS
  else
    grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$json_file" | sed 's/.*"id"[[:space:]]*:[[:space:]]*"//; s/"$//'
  fi
}

curl_json() {
  method="$1"
  url="$2"
  api_key="$3"
  body_file="${4:-}"
  output_file="$5"

  command -v curl >/dev/null 2>&1 || die "curl was not found."

  if [ "$method" = "GET" ]; then
    curl -sS \
      --connect-timeout "$REQUEST_TIMEOUT_SEC" \
      --max-time "$REQUEST_TIMEOUT_SEC" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -o "$output_file" \
      -w "%{http_code}" \
      "$url"
  else
    curl -sS \
      --connect-timeout "$REQUEST_TIMEOUT_SEC" \
      --max-time "$REQUEST_TIMEOUT_SEC" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -d "@$body_file" \
      -o "$output_file" \
      -w "%{http_code}" \
      "$url"
  fi
}

timed_curl_json() {
  method="$1"
  url="$2"
  api_key="$3"
  body_file="${4:-}"
  output_file="$5"
  timing_file="$6"

  command -v curl >/dev/null 2>&1 || die "curl was not found."

  if [ "$method" = "GET" ]; then
    result="$(curl -sS \
      --connect-timeout "$REQUEST_TIMEOUT_SEC" \
      --max-time "$REQUEST_TIMEOUT_SEC" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -o "$output_file" \
      -w "%{http_code} %{time_total}" \
      "$url")"
  else
    result="$(curl -sS \
      --connect-timeout "$REQUEST_TIMEOUT_SEC" \
      --max-time "$REQUEST_TIMEOUT_SEC" \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -d "@$body_file" \
      -o "$output_file" \
      -w "%{http_code} %{time_total}" \
      "$url")"
  fi

  printf '%s\n' "${result#* }" > "$timing_file"
  printf '%s\n' "${result%% *}"
}

http_failure_hint() {
  status="$1"
  case "$status" in
    400) warn "HTTP 400: request was rejected. The model name or Responses API compatibility may be wrong." ;;
    401) warn "HTTP 401: API key is missing or invalid." ;;
    402) warn "HTTP 402: quota, balance, or payment limit may be exhausted." ;;
    403) warn "HTTP 403: API key is valid but not allowed to use this resource." ;;
    404) warn "HTTP 404: endpoint not found. Check base URL and make sure it includes the correct /v1 path." ;;
    429) warn "HTTP 429: upstream rate limit or quota was reached." ;;
    5*) warn "HTTP $status: relay or upstream server error." ;;
    *) warn "HTTP $status: request failed." ;;
  esac
}

fetch_models_json() {
  base_url="$1"
  api_key="$2"
  output_file="$3"
  url="$(join_api_url "$base_url" "models")"
  status="$(curl_json "GET" "$url" "$api_key" "" "$output_file")"
  case "$status" in
    2*) return 0 ;;
    *) http_failure_hint "$status"; return 1 ;;
  esac
}

show_model_choices() {
  model_file="$1"
  awk 'NR <= 30 { printf "  %2d. %s\n", NR, $0 } NR == 31 { print "  ... showing first 30 models" }' "$model_file"
}

select_model() {
  base_url="$1"
  api_key="$2"
  requested_model="$3"

  if [ -n "$requested_model" ]; then
    printf '%s\n' "$requested_model"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ] || [ "$NO_MODEL_PICKER" -eq 1 ]; then
    printf '%s\n' "gpt-5.5"
    return
  fi

  json_tmp="$(mktemp)"
  model_tmp="$(mktemp)"
  if fetch_models_json "$base_url" "$api_key" "$json_tmp"; then
    parse_model_ids "$json_tmp" | sort -u > "$model_tmp"
    if [ -s "$model_tmp" ]; then
      if grep -qx "gpt-5.5" "$model_tmp"; then
        default_model="gpt-5.5"
      else
        default_model="$(sed -n '1p' "$model_tmp")"
      fi
      if [ -r /dev/tty ]; then
        printf '[codex-relay] Available models from relay:\n' > /dev/tty
        show_model_choices "$model_tmp" > /dev/tty
        printf 'Choose model number/name, or press Enter for %s: ' "$default_model" > /dev/tty
        IFS= read -r answer < /dev/tty
      else
        printf '[codex-relay] Available models from relay:\n' >&2
        show_model_choices "$model_tmp" >&2
        printf 'Choose model number/name, or press Enter for %s: ' "$default_model" >&2
        IFS= read -r answer
      fi
      if [ -z "$answer" ]; then
        printf '%s\n' "$default_model"
      elif printf '%s' "$answer" | grep -Eq '^[0-9]+$'; then
        chosen="$(sed -n "${answer}p" "$model_tmp")"
        if [ -n "$chosen" ]; then
          printf '%s\n' "$chosen"
        else
          warn "Model number out of range. Using $default_model."
          printf '%s\n' "$default_model"
        fi
      else
        printf '%s\n' "$answer"
      fi
      rm -f "$json_tmp" "$model_tmp"
      return
    fi
  fi

  rm -f "$json_tmp" "$model_tmp"
  warn "Could not fetch model list. Falling back to manual model input."
  if [ -r /dev/tty ]; then
    printf 'Default model [gpt-5.5]: ' > /dev/tty
    IFS= read -r manual < /dev/tty
  else
    printf 'Default model [gpt-5.5]: ' >&2
    IFS= read -r manual
  fi
  if [ -n "$manual" ]; then
    printf '%s\n' "$manual"
  else
    printf '%s\n' "gpt-5.5"
  fi
}

test_responses_connection() {
  base_url="$1"
  api_key="$2"
  model="$3"
  body_tmp="$(mktemp)"
  out_tmp="$(mktemp)"
  url="$(join_api_url "$base_url" "responses")"
  escaped_model="$(printf '%s' "$model" | json_escape)"
  cat > "$body_tmp" <<EOF
{
  "model": $escaped_model,
  "instructions": "Reply with OK only.",
  "input": "Connectivity test.",
  "stream": false
}
EOF
  status="$(curl_json "POST" "$url" "$api_key" "$body_tmp" "$out_tmp")"
  rm -f "$body_tmp" "$out_tmp"
  case "$status" in
    2*) log "Responses API test succeeded for model: $model"; return 0 ;;
    *) http_failure_hint "$status"; return 1 ;;
  esac
}

benchmark_result() {
  name="$1"
  status="$2"
  seconds="$3"
  ms="$(awk -v t="$seconds" 'BEGIN { printf "%.0f", t * 1000 }')"
  case "$status" in
    2*) log "$name: HTTP $status in ${ms} ms"; return 0 ;;
    *) warn "$name: HTTP $status after ${ms} ms"; return 1 ;;
  esac
}

invoke_benchmark() {
  resolved_base_url="$(normalize_base_url "$(prompt_value "Relay base URL, include /v1 if your service uses it" "$BASE_URL")")"
  if [ "$DRY_RUN" -eq 1 ]; then
    resolved_model="$(select_model "$resolved_base_url" "__dry_run_api_key_not_written__" "$MODEL")"
    log "Would benchmark: $(join_api_url "$resolved_base_url" "models")"
    log "Would benchmark: $(join_api_url "$resolved_base_url" "responses")"
    log "Would probe quota/spend endpoint: $(relay_root_url "$resolved_base_url")/global/spend/keys?limit=1"
    log "Would test model: $resolved_model"
    return
  fi

  api_key="$(prompt_secret)"
  resolved_model="$(select_model "$resolved_base_url" "$api_key" "$MODEL")"
  models_url="$(join_api_url "$resolved_base_url" "models")"
  responses_url="$(join_api_url "$resolved_base_url" "responses")"
  spend_url="$(relay_root_url "$resolved_base_url")/global/spend/keys?limit=1"

  log "Benchmark base URL: $resolved_base_url"
  log "Benchmark model: $resolved_model"

  models_out="$(mktemp)"
  models_time="$(mktemp)"
  models_status="$(timed_curl_json "GET" "$models_url" "$api_key" "" "$models_out" "$models_time")"
  models_seconds="$(cat "$models_time")"
  if ! benchmark_result "GET /models speed" "$models_status" "$models_seconds"; then
    http_failure_hint "$models_status"
    models_ok=0
  else
    models_ok=1
  fi

  body_tmp="$(mktemp)"
  responses_out="$(mktemp)"
  responses_time="$(mktemp)"
  escaped_model="$(printf '%s' "$resolved_model" | json_escape)"
  cat > "$body_tmp" <<EOF
{
  "model": $escaped_model,
  "instructions": "Reply with OK only.",
  "input": "One-time speed and quota probe.",
  "stream": false
}
EOF
  responses_status="$(timed_curl_json "POST" "$responses_url" "$api_key" "$body_tmp" "$responses_out" "$responses_time")"
  responses_seconds="$(cat "$responses_time")"
  if benchmark_result "POST /responses speed and quota status" "$responses_status" "$responses_seconds"; then
    log "Quota status: one minimal Responses request was accepted."
    responses_ok=1
  else
    http_failure_hint "$responses_status"
    responses_ok=0
  fi

  spend_out="$(mktemp)"
  spend_time="$(mktemp)"
  spend_status="$(timed_curl_json "GET" "$spend_url" "$api_key" "" "$spend_out" "$spend_time")"
  spend_seconds="$(cat "$spend_time")"
  if benchmark_result "GET /global/spend/keys quota metadata probe" "$spend_status" "$spend_seconds"; then
    log "Quota metadata endpoint is reachable for this key."
  else
    warn "Quota metadata endpoint is not readable with this key. This is normal for user keys; HTTP 401/403/404 here does not mean the relay request quota failed."
    http_failure_hint "$spend_status"
  fi

  rm -f "$models_out" "$models_time" "$body_tmp" "$responses_out" "$responses_time" "$spend_out" "$spend_time"

  if [ "$models_ok" -ne 1 ] || [ "$responses_ok" -ne 1 ]; then
    return 1
  fi
}

config_root_value() {
  key="$1"
  cfg="$(config_path)"
  [ -f "$cfg" ] || return 0
  awk -F '=' -v key="$key" '
    /^[[:space:]]*\[/ { exit }
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]*"/, "", value)
      sub(/"[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$cfg"
}

config_provider_value() {
  provider="$1"
  key="$2"
  cfg="$(config_path)"
  [ -f "$cfg" ] || return 0
  awk -F '=' -v header="[model_providers.$provider]" -v key="$key" '
    $0 == header { inside=1; next }
    inside && /^[[:space:]]*\[/ { exit }
    inside && $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value=$2
      sub(/^[[:space:]]*"/, "", value)
      sub(/"[[:space:]]*$/, "", value)
      print value
      exit
    }
  ' "$cfg"
}

remove_managed_config() {
  input_file="$1"
  remove_top_level_defaults="$2"

  if [ ! -f "$input_file" ]; then
    return 0
  fi

  awk \
    -v begin="$BEGIN_MARKER" \
    -v end="$END_MARKER" \
    -v remove_top="$remove_top_level_defaults" '
      $0 == begin { inside = 1; next }
      $0 == end { inside = 0; next }
      inside { next }
      !seen_table && $0 ~ /^[[:space:]]*\[/ { seen_table = 1 }
      remove_top == "1" && !seen_table && $0 ~ /^[[:space:]]*(model|model_provider|model_reasoning_effort)[[:space:]]*=/ { next }
      { print }
    ' "$input_file"
}

remove_relay_provider_config() {
  input_file="$1"
  output_file="$2"

  awk -v provider="$PROVIDER_ID" '
    function table_name(line, name) {
      name = line
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\][[:space:]]*$/, "", name)
      sub(/^[[:space:]]+/, "", name)
      sub(/[[:space:]]+$/, "", name)
      return name
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      current_table = table_name($0)
      if (current_table == "model_providers." provider || current_table == "model_providers.\"" provider "\"") {
        inside_target_provider = 1
        next
      }
      inside_target_provider = 0
    }
    inside_target_provider { next }
    { print }
  ' "$input_file" > "$output_file"
}

remove_project_config() {
  input_file="$1"
  output_file="$2"
  project_path="$3"

  if [ ! -f "$input_file" ]; then
    : > "$output_file"
    return
  fi

  awk -v project="$project_path" '
    function table_name(line, name) {
      name = line
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\][[:space:]]*$/, "", name)
      return name
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      current_table = table_name($0)
      if (current_table == "projects.\"" project "\"" || current_table == "projects.\047" project "\047") {
        inside_target_project = 1
        next
      }
      inside_target_project = 0
    }
    inside_target_project { next }
    { print }
  ' "$input_file" > "$output_file"
}

managed_root_block() {
  escaped_model="$(toml_escape "$MODEL")"

  cat <<EOF
$BEGIN_MARKER
model = "$escaped_model"
model_provider = "$PROVIDER_ID"
model_reasoning_effort = "xhigh"
$END_MARKER
EOF
}

trusted_project_block() {
  escaped_project_path="$(toml_escape "$project_path")"

  cat <<EOF
[projects."$escaped_project_path"]
trust_level = "trusted"
EOF
}

managed_provider_block() {
  escaped_provider_name="$(toml_escape "$PROVIDER_ID")"
  escaped_base_url="$(toml_escape "$BASE_URL")"
  escaped_api_key="$(toml_escape "$api_key")"

  cat <<EOF
$BEGIN_MARKER
[model_providers.$PROVIDER_ID]
name = "$escaped_provider_name"
base_url = "$escaped_base_url"
wire_api = "responses"
experimental_bearer_token = "$escaped_api_key"
$END_MARKER
EOF
}

split_config_at_first_table() {
  input_file="$1"
  root_file="$2"
  table_file="$3"

  : > "$root_file"
  : > "$table_file"
  [ -f "$input_file" ] || return 0

  awk -v root_file="$root_file" -v table_file="$table_file" '
    !seen_table && $0 ~ /^[[:space:]]*\[/ { seen_table = 1 }
    seen_table { print > table_file; next }
    { print > root_file }
  ' "$input_file"
}

ensure_windows_sandbox_config() {
  input_file="$1"
  output_file="$2"

  awk -v sandbox_line="$WINDOWS_SANDBOX_LINE" '
    function table_name(line, name) {
      name = line
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\][[:space:]]*$/, "", name)
      return name
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
      current_table = table_name($0)
      print
      if (current_table == "windows") {
        found_windows = 1
        print sandbox_line
      }
      next
    }
    /^[[:space:]]*sandbox[[:space:]]*=/ { next }
    { print }
    END {
      if (!found_windows) {
        if (NR > 0) {
          print ""
        }
        print "[windows]"
        print sandbox_line
      }
    }
  ' "$input_file" > "$output_file"
}

join_config_sections() {
  first=1
  for section_file in "$@"; do
    [ -s "$section_file" ] || continue
    if [ "$first" -eq 0 ]; then
      printf '\n'
    fi
    cat "$section_file"
    printf '\n'
    first=0
  done
}

latest_backup() {
  cfg="$(config_path)"
  dir="$(dirname "$cfg")"
  leaf="$(basename "$cfg")"
  [ -d "$dir" ] || return 1
  find "$dir" -maxdepth 1 -type f -name "$leaf.backup-*" -print 2>/dev/null | sort | tail -n 1
}

backup_config() {
  cfg="$(config_path)"
  [ -f "$cfg" ] || return 0
  backup="$cfg.backup-$(date +%Y%m%d-%H%M%S)"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would back up $cfg to $backup"
  else
    cp "$cfg" "$backup"
    log "Backed up config to $backup"
  fi
}

restore_config() {
  cfg="$(config_path)"
  backup="$(latest_backup || true)"
  [ -n "$backup" ] || die "No backup found for $cfg"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would restore $cfg from $backup"
    return
  fi

  mkdir -p "$(dirname "$cfg")"
  cp "$backup" "$cfg"
  log "Restored config from $backup"
}

answer_yes() {
  prompt="$1"
  if [ -r /dev/tty ]; then
    printf '%s [y/N]: ' "$prompt" > /dev/tty
    IFS= read -r answer < /dev/tty
  else
    printf '%s [y/N]: ' "$prompt" >&2
    IFS= read -r answer
  fi

  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_codex_cli() {
  [ "$SKIP_CODEX_CHECK" -eq 1 ] && return

  if command -v codex >/dev/null 2>&1; then
    log "Found Codex CLI: $(command -v codex)"
    return
  fi

  warn "Codex CLI was not found on PATH."
  if ! answer_yes "Install Codex CLI now with npm i -g @openai/codex?"; then
    warn "Skipping Codex CLI install. Install it later with: npm i -g @openai/codex"
    return
  fi

  ensure_npm_available
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would run: npm i -g @openai/codex"
  else
    npm i -g @openai/codex
  fi
}

load_nvm_if_available() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
  fi
}

install_node_runtime() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would install Node.js LTS with nvm if npm is missing."
    return
  fi

  load_nvm_if_available
  if ! command -v nvm >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || die "npm was not found and curl is unavailable. Install Node.js LTS from https://nodejs.org/ or use NodeSource, then rerun this installer."
    if ! answer_yes "npm was not found. Install nvm and Node.js LTS now?"; then
      die "Node.js and npm are required to install Codex CLI. Install Node.js LTS, then rerun this installer."
    fi
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    load_nvm_if_available
  fi

  command -v nvm >/dev/null 2>&1 || die "nvm installation finished but nvm is not available in this shell. Open a new terminal and rerun this installer."
  nvm install --lts
  nvm use --lts
}

ensure_npm_available() {
  if command -v npm >/dev/null 2>&1; then
    return
  fi

  warn "npm was not found. Node.js LTS is required before Codex CLI can be installed."
  warn "Linux users can also install Node.js through NodeSource if they prefer a system package."
  install_node_runtime

  if ! command -v npm >/dev/null 2>&1; then
    die "Node.js LTS installation finished, but npm is not available in this shell. Open a new terminal and rerun this installer."
  fi
}

invoke_doctor() {
  cfg="$(config_path)"
  configured_provider="$(config_root_value "model_provider")"
  [ -n "$configured_provider" ] || configured_provider="$PROVIDER_ID"
  configured_model="$(config_root_value "model")"
  configured_base_url="$(config_provider_value "$configured_provider" "base_url")"
  configured_api_key="$(config_provider_value "$configured_provider" "experimental_bearer_token")"
  effective_base_url="${BASE_URL:-$configured_base_url}"

  log "Codex home: $(codex_home)"
  log "Config path: $cfg"
  if [ -f "$cfg" ]; then
    log "Config exists: true"
  else
    warn "Config exists: false"
  fi

  if command -v codex >/dev/null 2>&1; then
    log "Codex CLI: $(command -v codex)"
    codex_version="$(codex --version 2>/dev/null || true)"
    [ -n "$codex_version" ] && log "Codex version: $codex_version"
  else
    warn "Codex CLI not found on PATH."
  fi

  api_key="$configured_api_key"
  log "Configured provider: $configured_provider"
  log "Configured model: $configured_model"
  log "Configured base URL: $effective_base_url"
  log "API key stored in config: $([ -n "$api_key" ] && printf true || printf false)"
  if [ -n "$api_key" ]; then
    :
  else
    warn "API key missing from config."
  fi

  if [ -n "$effective_base_url" ] && [ -n "$api_key" ]; then
    json_tmp="$(mktemp)"
    if fetch_models_json "$effective_base_url" "$api_key" "$json_tmp"; then
      count="$(parse_model_ids "$json_tmp" | wc -l | tr -d ' ')"
      log "Models endpoint reachable. Models returned: $count"
    else
      warn "Models endpoint check failed."
    fi
    rm -f "$json_tmp"
  else
    warn "Skipping network checks because base URL or API key is missing."
  fi
}

invoke_list_models() {
  resolved_base_url="$(normalize_base_url "$(prompt_value "Relay base URL, include /v1 if your service uses it" "$BASE_URL")")"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would request: $(join_api_url "$resolved_base_url" "models")"
    return
  fi

  api_key="$(prompt_secret)"
  json_tmp="$(mktemp)"
  model_tmp="$(mktemp)"
  if fetch_models_json "$resolved_base_url" "$api_key" "$json_tmp"; then
    parse_model_ids "$json_tmp" | sort -u > "$model_tmp"
    if [ -s "$model_tmp" ]; then
      show_model_choices "$model_tmp"
    else
      warn "Models endpoint returned no model IDs."
    fi
  else
    rm -f "$json_tmp" "$model_tmp"
    return 1
  fi
  rm -f "$json_tmp" "$model_tmp"
}

invoke_test_connection() {
  resolved_base_url="$(normalize_base_url "$(prompt_value "Relay base URL, include /v1 if your service uses it" "$BASE_URL")")"
  if [ "$DRY_RUN" -eq 1 ]; then
    resolved_model="$(select_model "$resolved_base_url" "__dry_run_api_key_not_written__" "$MODEL")"
    log "Would request: $(join_api_url "$resolved_base_url" "responses")"
    log "Would test model: $resolved_model"
    return
  fi

  api_key="$(prompt_secret)"
  resolved_model="$(select_model "$resolved_base_url" "$api_key" "$MODEL")"
  test_responses_connection "$resolved_base_url" "$api_key" "$resolved_model"
}

install_relay_config() {
  assert_provider_id

  BASE_URL="$(normalize_base_url "$BASE_URL")"
  if [ "$DRY_RUN" -eq 1 ]; then
    api_key="__dry_run_api_key_not_written__"
  else
    api_key="$(prompt_secret)"
  fi
  MODEL="$(select_model "$BASE_URL" "$api_key" "$MODEL")"
  project_path="$(pwd -P)"

  ensure_codex_cli

  cfg="$(config_path)"
  mkdir_arg="$(dirname "$cfg")"
  clean_tmp="$(mktemp)"
  provider_clean_tmp="$(mktemp)"
  sandbox_tmp="$(mktemp)"
  project_clean_tmp="$(mktemp)"
  root_tmp="$(mktemp)"
  table_tmp="$(mktemp)"
  root_block_tmp="$(mktemp)"
  project_block_tmp="$(mktemp)"
  provider_block_tmp="$(mktemp)"
  next_tmp="$(mktemp)"

  remove_managed_config "$cfg" "1" > "$clean_tmp"
  remove_relay_provider_config "$clean_tmp" "$provider_clean_tmp"
  remove_project_config "$provider_clean_tmp" "$project_clean_tmp" "$project_path"
  ensure_windows_sandbox_config "$project_clean_tmp" "$sandbox_tmp"
  split_config_at_first_table "$sandbox_tmp" "$root_tmp" "$table_tmp"
  managed_root_block > "$root_block_tmp"
  trusted_project_block > "$project_block_tmp"
  managed_provider_block > "$provider_block_tmp"
  join_config_sections "$root_block_tmp" "$root_tmp" "$project_block_tmp" "$table_tmp" "$provider_block_tmp" > "$next_tmp"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would write config to $cfg"
    printf '\n'
    cat "$next_tmp"
    log "Would store the relay API key in the Codex provider config."
    print_rerun_hints
    rm -f "$clean_tmp" "$provider_clean_tmp" "$project_clean_tmp" "$sandbox_tmp" "$root_tmp" "$table_tmp" "$root_block_tmp" "$project_block_tmp" "$provider_block_tmp" "$next_tmp"
    return
  fi

  mkdir -p "$mkdir_arg"
  backup_config
  cp "$next_tmp" "$cfg"
  rm -f "$clean_tmp" "$provider_clean_tmp" "$project_clean_tmp" "$sandbox_tmp" "$root_tmp" "$table_tmp" "$root_block_tmp" "$project_block_tmp" "$provider_block_tmp" "$next_tmp"

  log "Wrote Codex config: $cfg"
  log "Stored the relay API key in the Codex provider config."
  log "Restart VS Code and Codex Desktop so they reload config.toml."
  log "Try: codex --version && codex"
  print_rerun_hints
}

uninstall_relay_config() {
  cfg="$(config_path)"
  backup="$(latest_backup || true)"

  if [ -n "$backup" ]; then
    restore_config
  elif [ -f "$cfg" ]; then
    tmp="$(mktemp)"
    remove_managed_config "$cfg" "0" > "$tmp"
    if [ "$DRY_RUN" -eq 1 ]; then
      log "Would remove managed block from $cfg"
      rm -f "$tmp"
    else
      cp "$tmp" "$cfg"
      rm -f "$tmp"
      log "Removed managed config block from $cfg"
    fi
  else
    warn "No config file found at $cfg"
  fi

  log "No environment variables are managed by this installer."
}

if [ "$DOCTOR" -eq 1 ]; then
  invoke_doctor
elif [ "$TEST_CONNECTION" -eq 1 ]; then
  invoke_test_connection
elif [ "$BENCHMARK" -eq 1 ]; then
  invoke_benchmark
elif [ "$LIST_MODELS" -eq 1 ]; then
  invoke_list_models
elif [ "$RESTORE" -eq 1 ]; then
  restore_config
elif [ "$UNINSTALL" -eq 1 ]; then
  uninstall_relay_config
else
  install_relay_config
fi
