#!/usr/bin/env bash
set -euo pipefail

DEFAULT_BASE_URL="https://litellm.blackwhitedeer.studio"
DEFAULT_MODEL="gpt-5.5"
REQUEST_TIMEOUT_SEC=30
TARGET_OS="Linux"

DRY_RUN=0
UNINSTALL=0
RESTORE=0
DOCTOR=0
TEST_CONNECTION=0
LIST_MODELS=0
NO_MODEL_PICKER=0
SKIP_CLAUDE_CHECK=0
BASE_URL=""
MODEL=""

MANAGED_ENV_KEYS=(
  ANTHROPIC_BASE_URL
  ANTHROPIC_AUTH_TOKEN
  CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
  ANTHROPIC_MODEL
  ANTHROPIC_DEFAULT_SONNET_MODEL
  ANTHROPIC_DEFAULT_OPUS_MODEL
  ANTHROPIC_DEFAULT_HAIKU_MODEL
)

log() {
  printf '[claude-relay] %s\n' "$*"
}

warn() {
  printf '[claude-relay] WARNING: %s\n' "$*" >&2
}

die() {
  printf '[claude-relay] ERROR: %s\n' "$*" >&2
  exit 1
}

ensure_target_os() {
  actual_os="$(uname -s 2>/dev/null || true)"
  if [ "$actual_os" != "$TARGET_OS" ]; then
    die "This installer is for $TARGET_OS. Detected: ${actual_os:-unknown}."
  fi
}

usage() {
  cat <<'EOF'
Configure Claude Code CLI and the VS Code Claude Code extension to use a
Claude/Anthropic Messages-compatible relay.

Usage:
  bash "install-claude-code-relay-linux.sh" [options]

Options:
  --dry-run              Show what would be written.
  --doctor               Check Claude Code settings and relay reachability.
  --test                 Test /v1/models and /v1/messages.
  --list-models          List models from the relay.
  --restore              Restore the newest settings.json backup.
  --uninstall            Remove env keys managed by this installer.
  --base-url VALUE       Claude relay root URL. Default: https://litellm.blackwhitedeer.studio
  --model VALUE          Model name to pin in Claude Code settings.
  --no-model-picker      Do not prompt with the relay model list.
  --skip-claude-check    Do not check whether claude is in PATH.
  -h, --help             Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --doctor) DOCTOR=1 ;;
    --test|--test-connection) TEST_CONNECTION=1 ;;
    --list-models) LIST_MODELS=1 ;;
    --restore) RESTORE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --no-model-picker) NO_MODEL_PICKER=1 ;;
    --skip-claude-check) SKIP_CLAUDE_CHECK=1 ;;
    --base-url)
      shift
      [ "$#" -gt 0 ] || die "--base-url requires a value"
      BASE_URL="$1"
      ;;
    --model)
      shift
      [ "$#" -gt 0 ] || die "--model requires a value"
      MODEL="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

claude_home() {
  printf '%s/.claude\n' "$HOME"
}

settings_path() {
  printf '%s/settings.json\n' "$(claude_home)"
}

script_path_for_help() {
  if [ -n "${BASH_SOURCE[0]:-}" ]; then
    cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P | sed "s|$|/$(basename "${BASH_SOURCE[0]}")|"
    return
  fi
  printf '/path/to/install-claude-code-relay-linux.sh\n'
}

print_rerun_hints() {
  local script_path
  script_path="$(script_path_for_help)"
  log "Use the full installer path for future local runs:"
  log "  bash \"$script_path\" --doctor"
  log "  bash \"$script_path\" --test"
  log "  bash \"$script_path\" --uninstall"
}

normalize_base_url() {
  local value="${1:-}"
  if [ -z "$value" ]; then
    value="$DEFAULT_BASE_URL"
  fi
  value="${value%/}"
  case "$value" in
    */v1/messages) value="${value%/v1/messages}" ;;
    */messages) value="${value%/messages}" ;;
    */v1) value="${value%/v1}" ;;
  esac
  printf '%s\n' "${value%/}"
}

join_claude_url() {
  local base path
  base="$(normalize_base_url "$1")"
  path="${2#/}"
  printf '%s/v1/%s\n' "$base" "$path"
}

require_json_editor() {
  if command -v node >/dev/null 2>&1; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would use Node.js to edit settings.json."
    return 0
  fi
  ensure_npm_available
  command -v node >/dev/null 2>&1 || die "Node.js installation finished, but node is not available in this shell. Open a new terminal and rerun this installer."
}

answer_yes() {
  local prompt="$1" answer
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

load_nvm_if_available() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
  fi
}

run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_node_runtime() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would install Node.js LTS with the native Linux package manager if npm is missing."
    return
  fi

  if ! answer_yes "npm was not found. Install Node.js LTS now with the native Linux package manager?"; then
    die "Node.js and npm are required to update Claude Code settings JSON. Install Node.js LTS, then rerun this installer."
  fi

  if command -v apt-get >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || run_root apt-get update
    command -v curl >/dev/null 2>&1 || run_root apt-get install -y curl ca-certificates
    curl -fsSL https://deb.nodesource.com/setup_lts.x | run_root bash -
    run_root apt-get install -y nodejs
  elif command -v dnf >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || run_root dnf install -y curl ca-certificates
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | run_root bash -
    run_root dnf install -y nodejs
  elif command -v yum >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || run_root yum install -y curl ca-certificates
    curl -fsSL https://rpm.nodesource.com/setup_lts.x | run_root bash -
    run_root yum install -y nodejs
  elif command -v pacman >/dev/null 2>&1; then
    run_root pacman -Sy --noconfirm nodejs npm
  elif command -v zypper >/dev/null 2>&1; then
    run_root zypper install -y nodejs npm
  elif command -v apk >/dev/null 2>&1; then
    run_root apk add nodejs npm
  else
    die "No supported Linux package manager found. Install Node.js LTS from https://nodejs.org/, then rerun this installer."
  fi
}

ensure_npm_available() {
  if command -v npm >/dev/null 2>&1; then
    return
  fi

  warn "npm was not found. Node.js LTS is required before Claude Code CLI can be installed."
  install_node_runtime

  if ! command -v npm >/dev/null 2>&1; then
    die "Node.js LTS installation finished, but npm is not available in this shell. Open a new terminal and rerun this installer."
  fi
}

prompt_value() {
  local prompt="$1"
  local current="${2:-}"
  local value
  if [ -n "$current" ]; then
    printf '%s\n' "$current"
    return
  fi
  while true; do
    printf '%s: ' "$prompt" > /dev/tty
    IFS= read -r value < /dev/tty
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
    warn "Value cannot be empty."
  done
}

read_api_key() {
  local value
  while true; do
    printf 'Paste your Claude relay API key: ' > /dev/tty
    stty -echo < /dev/tty
    IFS= read -r value < /dev/tty
    stty echo < /dev/tty
    printf '\n' > /dev/tty
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return
    fi
    warn "API key cannot be empty."
  done
}

backup_settings() {
  local path backup
  path="$(settings_path)"
  [ -f "$path" ] || return 0
  backup="$path.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$path" "$backup"
  log "Backup created: $backup"
}

get_settings_value() {
  local key="$1"
  local path
  path="$(settings_path)"
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

write_settings() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"
  require_json_editor
  mkdir -p "$(claude_home)"
  SETTINGS_PATH="$(settings_path)" \
  CLAUDE_RELAY_BASE_URL="$base_url" \
  CLAUDE_RELAY_API_KEY="$api_key" \
  CLAUDE_RELAY_MODEL="$model" \
  node <<'NODE'
const fs = require("fs");
const path = process.env.SETTINGS_PATH;
let settings = {};
if (fs.existsSync(path)) {
  const raw = fs.readFileSync(path, "utf8").trim();
  if (raw) settings = JSON.parse(raw);
}
if (!settings.env || typeof settings.env !== "object" || Array.isArray(settings.env)) {
  settings.env = {};
}
settings.env.ANTHROPIC_BASE_URL = process.env.CLAUDE_RELAY_BASE_URL;
settings.env.ANTHROPIC_AUTH_TOKEN = process.env.CLAUDE_RELAY_API_KEY;
settings.env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
settings.env.ANTHROPIC_MODEL = process.env.CLAUDE_RELAY_MODEL;
settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL = process.env.CLAUDE_RELAY_MODEL;
settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL = process.env.CLAUDE_RELAY_MODEL;
settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = process.env.CLAUDE_RELAY_MODEL;
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
NODE
}

remove_managed_settings() {
  require_json_editor
  local keys_json path
  path="$(settings_path)"
  [ -f "$path" ] || {
    log "Settings file does not exist; nothing to uninstall."
    return
  }
  keys_json="$(printf '%s\n' "${MANAGED_ENV_KEYS[@]}" | node -e 'const fs=require("fs"); console.log(JSON.stringify(fs.readFileSync(0,"utf8").trim().split(/\n/).filter(Boolean)))')"
  SETTINGS_PATH="$path" MANAGED_KEYS="$keys_json" node <<'NODE'
const fs = require("fs");
const path = process.env.SETTINGS_PATH;
const keys = JSON.parse(process.env.MANAGED_KEYS);
const raw = fs.readFileSync(path, "utf8").trim();
const settings = raw ? JSON.parse(raw) : {};
if (settings.env && typeof settings.env === "object") {
  for (const key of keys) delete settings.env[key];
}
fs.writeFileSync(path, JSON.stringify(settings, null, 2) + "\n");
NODE
  log "Removed Claude relay env keys from settings.json."
}

curl_json() {
  local method="$1"
  local url="$2"
  local api_key="$3"
  local body="${4:-}"
  if [ "$method" = "GET" ]; then
    curl -sS -m "$REQUEST_TIMEOUT_SEC" \
      -H "Authorization: Bearer $api_key" \
      "$url"
  else
    curl -sS -m "$REQUEST_TIMEOUT_SEC" \
      -X "$method" \
      -H "Authorization: Bearer $api_key" \
      -H "anthropic-version: 2023-06-01" \
      -H "Content-Type: application/json" \
      -d "$body" \
      "$url"
  fi
}

get_models() {
  local base_url="$1"
  local api_key="$2"
  local url json
  url="$(join_claude_url "$base_url" "models")"
  json="$(curl_json GET "$url" "$api_key")"
  printf '%s' "$json" | node -e '
const fs = require("fs");
const raw = fs.readFileSync(0, "utf8");
const data = JSON.parse(raw);
if (data.error) throw new Error(JSON.stringify(data.error));
const ids = Array.isArray(data.data) ? data.data.map((m) => m && m.id).filter(Boolean) : [];
console.log([...new Set(ids)].sort().join("\n"));
'
}

show_model_choices() {
  local count=0
  while IFS= read -r model; do
    [ -n "$model" ] || continue
    count=$((count + 1))
    [ "$count" -le 30 ] || continue
    printf '  %2d. %s\n' "$count" "$model"
  done
}

select_model() {
  local base_url="$1"
  local api_key="$2"
  local requested="${3:-}"
  local models default answer index selected
  if [ -n "$requested" ]; then
    printf '%s\n' "$requested"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ] || [ "$NO_MODEL_PICKER" -eq 1 ]; then
    printf '%s\n' "$DEFAULT_MODEL"
    return
  fi
  if models="$(get_models "$base_url" "$api_key" 2>/dev/null)" && [ -n "$models" ]; then
    default="$(printf '%s\n' "$models" | grep -Fx "$DEFAULT_MODEL" || true)"
    [ -n "$default" ] || default="$(printf '%s\n' "$models" | sed -n '1p')"
    log "Available models from relay:"
    printf '%s\n' "$models" | show_model_choices
    printf 'Choose model number/name, or press Enter for %s: ' "$default" > /dev/tty
    IFS= read -r answer < /dev/tty
    if [ -z "$answer" ]; then
      printf '%s\n' "$default"
      return
    fi
    case "$answer" in
      ''|*[!0-9]*)
        printf '%s\n' "$answer"
        return
        ;;
      *)
        index="$answer"
        selected="$(printf '%s\n' "$models" | sed -n "${index}p")"
        if [ -n "$selected" ]; then
          printf '%s\n' "$selected"
        else
          warn "Model number out of range. Using $default."
          printf '%s\n' "$default"
        fi
        return
        ;;
    esac
  fi
  printf 'Default model [%s]: ' "$DEFAULT_MODEL" > /dev/tty
  IFS= read -r answer < /dev/tty
  [ -n "$answer" ] && printf '%s\n' "$answer" || printf '%s\n' "$DEFAULT_MODEL"
}

test_messages_connection() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"
  local url body json type content_type
  url="$(join_claude_url "$base_url" "messages")"
  body="$(node -e 'console.log(JSON.stringify({model: process.argv[1], max_tokens: 16, messages: [{role: "user", content: "Reply with OK only."}]}))' "$model")"
  json="$(curl_json POST "$url" "$api_key" "$body")"
  type="$(printf '%s' "$json" | node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(0,"utf8")); if(data.error) throw new Error(JSON.stringify(data.error)); process.stdout.write(String(data.type || ""));')"
  content_type="$(printf '%s' "$json" | node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(0,"utf8")); process.stdout.write(String(data.content && data.content[0] && data.content[0].type || ""));')"
  if [ "$type" != "message" ] || [ -z "$content_type" ]; then
    die "Relay returned a response, but it did not look like an Anthropic Messages response."
  fi
  log "Anthropic Messages test succeeded for model: $model"
}

ensure_claude_cli() {
  [ "$SKIP_CLAUDE_CHECK" -eq 0 ] || return 0
  if command -v claude >/dev/null 2>&1; then
    log "Found Claude CLI: $(command -v claude)"
    claude --version 2>/dev/null | sed 's/^/[claude-relay] Claude CLI version: /' || true
    return 0
  fi
  warn "Claude CLI was not found on PATH."
  if ! answer_yes "Install Claude Code CLI now with the official command (curl -fsSL https://claude.ai/install.sh | bash)?"; then
    warn "Skipping Claude Code CLI install. Install it later with: curl -fsSL https://claude.ai/install.sh | bash"
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would run: curl -fsSL https://claude.ai/install.sh | bash"
    return 0
  fi

  if curl -fsSL https://claude.ai/install.sh | bash; then
    return 0
  fi

  die "Official Claude Code installer failed. Rerun the official command or check network access to https://claude.ai/install.sh."
}

invoke_doctor() {
  local path base api_key model models
  path="$(settings_path)"
  base="${BASE_URL:-$(get_settings_value ANTHROPIC_BASE_URL || true)}"
  base="$(normalize_base_url "${base:-$DEFAULT_BASE_URL}")"
  api_key="$(get_settings_value ANTHROPIC_AUTH_TOKEN || true)"
  model="${MODEL:-$(get_settings_value ANTHROPIC_MODEL || true)}"
  [ -n "$model" ] || model="$DEFAULT_MODEL"
  log "Claude home: $(claude_home)"
  log "Settings path: $path"
  log "Settings exists: $([ -f "$path" ] && printf true || printf false)"
  log "Configured base URL: $base"
  log "API key stored in settings: $([ -n "$api_key" ] && printf true || printf false)"
  log "Configured model: $model"
  ensure_claude_cli
  if [ -n "$api_key" ]; then
    if models="$(get_models "$base" "$api_key" 2>/dev/null)"; then
      log "Model endpoint reachable. Model count: $(printf '%s\n' "$models" | sed '/^$/d' | wc -l | tr -d ' ')"
    else
      warn "Model endpoint check failed."
    fi
  else
    warn "No API key found in settings; skipping authenticated relay check."
  fi
}

invoke_list_models() {
  local base api_key models
  base="$(normalize_base_url "$(prompt_value "Claude relay base URL" "$BASE_URL")")"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would request: $(join_claude_url "$base" "models")"
    return
  fi
  api_key="$(read_api_key)"
  models="$(get_models "$base" "$api_key")"
  if [ -z "$models" ]; then
    warn "No models returned."
    return
  fi
  printf '%s\n' "$models" | show_model_choices
}

invoke_test_connection() {
  local base api_key model
  base="$(normalize_base_url "$(prompt_value "Claude relay base URL" "$BASE_URL")")"
  api_key="$([ "$DRY_RUN" -eq 1 ] && printf '__dry_run_api_key_not_written__' || read_api_key)"
  model="$(select_model "$base" "$api_key" "$MODEL")"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would request: $(join_claude_url "$base" "models")"
    log "Would request: $(join_claude_url "$base" "messages")"
    log "Would test model: $model"
    return
  fi
  get_models "$base" "$api_key" >/dev/null
  test_messages_connection "$base" "$api_key" "$model"
}

invoke_restore() {
  local path backup
  path="$(settings_path)"
  backup="$(ls -t "$path".backup-* 2>/dev/null | sed -n '1p' || true)"
  if [ -z "$backup" ]; then
    warn "No backup found."
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would restore: $backup -> $path"
    return
  fi
  cp "$backup" "$path"
  log "Restored latest backup: $backup"
}

invoke_uninstall() {
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would remove Claude relay env keys from: $(settings_path)"
    return
  fi
  backup_settings
  remove_managed_settings
}

invoke_install() {
  local base api_key model path
  require_json_editor
  ensure_claude_cli
  base="$(normalize_base_url "$(prompt_value "Claude relay base URL [$DEFAULT_BASE_URL]" "$BASE_URL")")"
  api_key="$([ "$DRY_RUN" -eq 1 ] && printf '__dry_run_api_key_not_written__' || read_api_key)"
  model="$(select_model "$base" "$api_key" "$MODEL")"
  path="$(settings_path)"
  if [ "$DRY_RUN" -eq 0 ]; then
    test_messages_connection "$base" "$api_key" "$model"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log "Would write Claude Code settings to: $path"
    log "Base URL: $base"
    log "Model: $model"
    log "API key would be stored as ANTHROPIC_AUTH_TOKEN."
    return
  fi
  backup_settings
  write_settings "$base" "$api_key" "$model"
  log "Wrote Claude Code settings: $path"
  log "Base URL: $base"
  log "Model: $model"
  log "Restart VS Code and Claude Code so they reload ~/.claude/settings.json."
  log "Try: claude --version && claude"
  print_rerun_hints
}

ensure_target_os

if [ "$RESTORE" -eq 1 ]; then
  invoke_restore
  exit 0
fi
if [ "$UNINSTALL" -eq 1 ]; then
  invoke_uninstall
  exit 0
fi
if [ "$DOCTOR" -eq 1 ]; then
  invoke_doctor
  exit 0
fi
if [ "$LIST_MODELS" -eq 1 ]; then
  invoke_list_models
  exit 0
fi
if [ "$TEST_CONNECTION" -eq 1 ]; then
  invoke_test_connection
  exit 0
fi

invoke_install
