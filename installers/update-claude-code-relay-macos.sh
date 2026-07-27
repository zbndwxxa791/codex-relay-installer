#!/usr/bin/env bash
# Refresh the custom relay model list for Claude Code on macOS.
# Automatic source: OpenAI-compatible /v1/models.
# Manual sources: --models, --models-file, or --manual.

set -euo pipefail
umask 077

TARGET_OS="Darwin"
DEFAULT_BASE_URL="https://litellm.blackwhitedeer.studio"
DISCOVERY_KEY="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"
MODE="refresh"
MODEL=""
MODELS_ARG=""
MODELS_ARG_SET=0
MODELS_FILE=""
MODELS_FILE_SET=0
MANUAL=0
BASE_URL_ARG=""
API_KEY_ARG=""
MODELS_URL=""
AUTH_MODE="auto"
USER_AGENT=""
REQUEST_TIMEOUT=15
DRY_RUN=0
LIST_MODELS=0
NO_PICKER=0

log() { printf '[claude-models] %s\n' "$1" >&2; }
warn() { printf '[claude-models] WARNING: %s\n' "$1" >&2; }
die() { printf '[claude-models] ERROR: %s\n' "$1" >&2; exit 1; }

print_help() {
  sed -n '1,/^set -euo pipefail$/p' "$0" | sed '1d;$d;s/^# *//'
  cat <<'USAGE'
Usage: update-claude-code-relay-macos.sh [options]
  --mode refresh|list|switch   Default: refresh
  --model ID                   Switch to ID without prompting
  --models "id-a,id-b"         Manual comma-separated IDs
  --models-file PATH           Text or JSON model list
  --manual                     Enter one model ID per line
  --base-url URL               Override configured relay URL
  --api-key KEY                Override configured API key
  --models-url URL             Use an exact models endpoint
  --auth-mode auto|bearer|x-api-key
  --user-agent VALUE
  --timeout SECONDS            Default: 15
  --dry-run
  --list-models
  --no-picker
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) [ "$#" -ge 2 ] || die "--mode requires a value"; MODE="$2"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    --model) [ "$#" -ge 2 ] || die "--model requires a value"; MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#*=}"; shift ;;
    --models) [ "$#" -ge 2 ] || die "--models requires a value"; MODELS_ARG="$2"; MODELS_ARG_SET=1; shift 2 ;;
    --models=*) MODELS_ARG="${1#*=}"; MODELS_ARG_SET=1; shift ;;
    --models-file) [ "$#" -ge 2 ] || die "--models-file requires a value"; MODELS_FILE="$2"; MODELS_FILE_SET=1; shift 2 ;;
    --models-file=*) MODELS_FILE="${1#*=}"; MODELS_FILE_SET=1; shift ;;
    --manual) MANUAL=1; shift ;;
    --base-url) [ "$#" -ge 2 ] || die "--base-url requires a value"; BASE_URL_ARG="$2"; shift 2 ;;
    --base-url=*) BASE_URL_ARG="${1#*=}"; shift ;;
    --api-key) [ "$#" -ge 2 ] || die "--api-key requires a value"; API_KEY_ARG="$2"; shift 2 ;;
    --api-key=*) API_KEY_ARG="${1#*=}"; shift ;;
    --models-url) [ "$#" -ge 2 ] || die "--models-url requires a value"; MODELS_URL="$2"; shift 2 ;;
    --models-url=*) MODELS_URL="${1#*=}"; shift ;;
    --auth-mode) [ "$#" -ge 2 ] || die "--auth-mode requires a value"; AUTH_MODE="$2"; shift 2 ;;
    --auth-mode=*) AUTH_MODE="${1#*=}"; shift ;;
    --user-agent) [ "$#" -ge 2 ] || die "--user-agent requires a value"; USER_AGENT="$2"; shift 2 ;;
    --user-agent=*) USER_AGENT="${1#*=}"; shift ;;
    --timeout) [ "$#" -ge 2 ] || die "--timeout requires a value"; REQUEST_TIMEOUT="$2"; shift 2 ;;
    --timeout=*) REQUEST_TIMEOUT="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list-models) LIST_MODELS=1; shift ;;
    --no-picker) NO_PICKER=1; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

case "$MODE" in refresh|list|switch) ;; *) die "--mode must be refresh, list, or switch" ;; esac
case "$AUTH_MODE" in auto|bearer|x-api-key) ;; *) die "--auth-mode must be auto, bearer, or x-api-key" ;; esac
case "$REQUEST_TIMEOUT" in ''|*[!0-9]*) die "--timeout must be a positive integer" ;; esac
[ "$REQUEST_TIMEOUT" -gt 0 ] || die "--timeout must be a positive integer"

ensure_target_os() {
  local actual_os
  actual_os="$(uname -s)"
  [ "$actual_os" = "$TARGET_OS" ] || die "This script targets $TARGET_OS, but uname reported $actual_os."
}

require_node() { command -v node >/dev/null 2>&1 || die "Node.js is required. Run the relay installer first."; }

CLAUDE_HOME_PATH="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS_PATH="$CLAUDE_HOME_PATH/settings.json"
CACHE_PATH="$CLAUDE_HOME_PATH/cache/gateway-models.json"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-models.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT INT TERM
MODELS_JSON="$WORK_DIR/models.json"
SETTINGS_STATE="$WORK_DIR/settings-state.json"
RESPONSE_FILE="$WORK_DIR/response.json"

normalize_models() {
  local source_kind="$1" source_value="$2"
  RELAY_MODEL_SOURCE_KIND="$source_kind" RELAY_MODEL_SOURCE_VALUE="$source_value" node - >"$MODELS_JSON" <<'NODE'
const fs = require('fs');
const kind = process.env.RELAY_MODEL_SOURCE_KIND;
const value = process.env.RELAY_MODEL_SOURCE_VALUE || '';
let input;
if (kind === 'direct') input = value.split(',');
else {
  const raw = fs.readFileSync(value, 'utf8');
  const trimmed = raw.trim();
  if (!trimmed) throw new Error('Model source is empty.');
  if (kind === 'network' && !(trimmed.startsWith('{') || trimmed.startsWith('['))) throw new Error('Model endpoint returned a non-JSON response.');
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) input = JSON.parse(raw);
  else input = raw.split(/\r?\n/).map(line => line.trim()).filter(line => line && !line.startsWith('#'));
}
if (input && !Array.isArray(input)) {
  if (Array.isArray(input.data)) input = input.data;
  else if (Array.isArray(input.models)) input = input.models;
  else if (kind === 'network') throw new Error('Model endpoint JSON must be an array or contain data/models.');
  else input = [input];
}
const byId = new Map();
for (const item of input || []) {
  const object = typeof item === 'string' ? {id: item} : item;
  const id = String(object && object.id || '').trim();
  if (!id) throw new Error('Model ID cannot be empty.');
  if (/[\x00-\x1f\x7f]/.test(id)) throw new Error(`Model ID contains a control character: ${JSON.stringify(id)}`);
  if (byId.has(id)) continue;
  let context = object.context_window ?? object.contextWindow ?? null;
  if (context !== null) {
    context = Number(context);
    if (!Number.isInteger(context) || context < 1) throw new Error(`Invalid context_window for ${id}`);
  }
  byId.set(id, {
    id,
    display_name: String(object.display_name || object.displayName || id),
    owned_by: object.owned_by ? String(object.owned_by) : null,
    context_window: context
  });
}
const models = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id, 'en'));
if (!models.length) throw new Error('No valid models were supplied.');
process.stdout.write(JSON.stringify(models, null, 2) + '\n');
NODE
}

read_manual_models() {
  [ -t 0 ] || die "--manual requires an interactive terminal"
  local manual_file="$WORK_DIR/manual.txt" value
  : >"$manual_file"
  log "Enter one model ID per line. Submit an empty line to finish."
  while true; do
    printf 'Model ID: ' >&2
    IFS= read -r value || die "stdin closed while reading model IDs"
    [ -n "$value" ] || break
    printf '%s\n' "$value" >>"$manual_file"
  done
  normalize_models file "$manual_file"
}

read_settings() {
  RELAY_DEFAULT_BASE="$DEFAULT_BASE_URL" node - "$SETTINGS_PATH" >"$SETTINGS_STATE" <<'NODE'
const fs=require('fs'); const path=process.argv[2]; let settings={};
try { settings=JSON.parse(fs.readFileSync(path,'utf8')); } catch (error) { if(error.code!=='ENOENT') throw error; }
const env=settings.env&&typeof settings.env==='object'?settings.env:{};
let apiKey='',authMode='bearer';
if(env.ANTHROPIC_AUTH_TOKEN){apiKey=String(env.ANTHROPIC_AUTH_TOKEN);authMode='bearer';}
else if(env.ANTHROPIC_API_KEY){apiKey=String(env.ANTHROPIC_API_KEY);authMode='x-api-key';}
process.stdout.write(JSON.stringify({baseUrl:String(env.ANTHROPIC_BASE_URL||process.env.RELAY_DEFAULT_BASE),apiKey,authMode,model:String(env.ANTHROPIC_MODEL||'')}));
NODE
}

json_field() { node -e "const x=require(process.argv[1]); process.stdout.write(String(x[process.argv[2]] || ''))" "$1" "$2"; }

CANDIDATES=()
add_candidate() {
  local candidate="$1" existing
  [ -n "$candidate" ] || return 0
  [ "${#CANDIDATES[@]}" -lt 3 ] || return 0
  for existing in "${CANDIDATES[@]:-}"; do [ "$existing" = "$candidate" ] && return 0; done
  CANDIDATES+=("$candidate")
}

build_candidates() {
  CANDIDATES=()
  if [ -n "$MODELS_URL" ]; then add_candidate "$MODELS_URL"; return; fi
  local normalized version root suffix
  normalized="${1%/}"
  if [[ "$normalized" =~ /v([0-9]+)$ ]]; then
    version="${BASH_REMATCH[1]}"; add_candidate "$normalized/models"
    [ "$version" = "1" ] || add_candidate "$normalized/v1/models"
  else add_candidate "$normalized/v1/models"
  fi
  for suffix in /api/claudecode /api/anthropic /apps/anthropic /api/coding /claudecode /anthropic /step_plan /coding /claude; do
    case "$normalized" in *"$suffix") root="${normalized%$suffix}"; root="${root%/}"; add_candidate "$root/v1/models"; add_candidate "$root/models"; break ;; esac
  done
}

safe_url_for_log() {
  node -e 'try { const u=new URL(process.argv[1]); u.username=""; u.password=""; u.search=""; u.hash=""; let value=u.origin+u.pathname; const secret=process.argv[2]||""; if(secret)value=value.split(secret).join("<redacted>"); process.stdout.write(value); } catch { process.stdout.write("<invalid URL>"); }' "$1" "$2"
}
fetch_models() {
  command -v curl >/dev/null 2>&1 || die "curl is required for automatic model discovery"
  local relay_base="$1" relay_key="$2" resolved_auth="$3" endpoint status safe_endpoint
  build_candidates "$relay_base"
  for endpoint in "${CANDIDATES[@]}"; do
    safe_endpoint="$(safe_url_for_log "$endpoint" "$relay_key")"
    log "Fetching model list: $safe_endpoint"
    local curl_args=(-sS -o "$RESPONSE_FILE" -w '%{http_code}' --max-time "$REQUEST_TIMEOUT" -H 'Accept: application/json')
    [ -z "$USER_AGENT" ] || curl_args+=(-H "User-Agent: $USER_AGENT")
    if [ -n "$relay_key" ]; then
      if [ "$resolved_auth" = "x-api-key" ]; then curl_args+=(-H "x-api-key: $relay_key")
      else curl_args+=(-H "Authorization: Bearer $relay_key")
      fi
    fi
    if ! status="$(curl "${curl_args[@]}" "$endpoint" 2>"$WORK_DIR/curl-error.txt")"; then die "Model endpoint request failed. Check connectivity, Base URL, and authentication."; fi
    if [ "$status" = "200" ]; then normalize_models network "$RESPONSE_FILE"; return; fi
    if [ "$status" = "404" ] || [ "$status" = "405" ]; then continue; fi
    die "Model endpoint returned HTTP $status."
  done
  die "All model endpoint candidates returned HTTP 404/405. Use --models, --models-file, or --manual."
}

show_models() { node -e "const m=require(process.argv[1]); m.forEach((x,i)=>console.log(String(i+1).padStart(4)+'. '+x.id))" "$MODELS_JSON"; }
first_model() { node -e "process.stdout.write(require(process.argv[1])[0].id)" "$MODELS_JSON"; }
contains_model() { node -e "process.exit(require(process.argv[1]).some(x=>x.id===process.argv[2])?0:1)" "$MODELS_JSON" "$1"; }
validate_model_id() { node -e 'const id=String(process.argv[1]||"").trim(); if(!id) throw new Error("Model ID cannot be empty."); if(/[\x00-\x1f\x7f]/.test(id)) throw new Error("Model ID contains a control character."); process.stdout.write(id);' "$1"; }

select_model() {
  local current="$1" answer position total default_model
  if [ -n "$MODEL" ]; then MODEL="$(validate_model_id "$MODEL")"; contains_model "$MODEL" || warn "Model '$MODEL' is not in the supplied list; writing it anyway."; printf '%s' "$MODEL"; return; fi
  if [ "$NO_PICKER" -eq 1 ]; then [ -n "$current" ] && validate_model_id "$current" || first_model; return; fi
  [ -t 0 ] || die "switch mode requires --model or --no-picker when stdin is redirected"
  show_models >&2
  if [ -n "$current" ] && contains_model "$current"; then default_model="$current"; else default_model="$(first_model)"; fi
  printf 'Choose model number/name, or press Enter for %s: ' "$default_model" >&2
  IFS= read -r answer
  [ -n "$answer" ] || { printf '%s' "$default_model"; return; }
  case "$answer" in
    *[!0-9]*) validate_model_id "$answer" ;;
    *) total="$(node -e "process.stdout.write(String(require(process.argv[1]).length))" "$MODELS_JSON")"; position=$((10#$answer - 1)); [ "$position" -ge 0 ] && [ "$position" -lt "$total" ] || die "Model number is out of range"; node -e "process.stdout.write(require(process.argv[1])[Number(process.argv[2])].id)" "$MODELS_JSON" "$position" ;;
  esac
}

backup_file() {
  local path="$1" stamp backup
  [ -f "$path" ] || return 0
  stamp="$(date +%Y%m%d-%H%M%S)"; backup="$path.backup-$stamp-$RANDOM"
  while [ -e "$backup" ]; do backup="$path.backup-$stamp-$RANDOM"; done; cp -p "$path" "$backup"; log "Backup: $backup"
}

atomic_copy() {
  local source="$1" target="$2" target_dir temporary mode
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  temporary="$target.tmp.$$"
  cp "$source" "$temporary"
  if [ -f "$target" ]; then
    if [ "$TARGET_OS" = "Darwin" ]; then mode="$(stat -f '%Lp' "$target")"; else mode="$(stat -c '%a' "$target")"; fi
    chmod "$mode" "$temporary"
  else
    chmod 600 "$temporary"
  fi
  mv -f "$temporary" "$target"
}

generate_settings_and_cache() {
  RELAY_RUN_MODE="$1" RELAY_SELECTED_MODEL="$2" RELAY_DISCOVERY_KEY="$DISCOVERY_KEY" RELAY_BASE_URL="$3" \
  node - "$SETTINGS_PATH" "$MODELS_JSON" "$WORK_DIR/settings.out.json" "$WORK_DIR/cache.out.json" <<'NODE'
const fs=require('fs'); const [settingsPath,modelsPath,settingsOut,cacheOut]=process.argv.slice(2); let settings={};
try{settings=JSON.parse(fs.readFileSync(settingsPath,'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
if(!settings.env||typeof settings.env!=='object'||Array.isArray(settings.env))settings.env={};
const env=settings.env,models=JSON.parse(fs.readFileSync(modelsPath,'utf8'));
env[process.env.RELAY_DISCOVERY_KEY]='1';
if(process.env.RELAY_RUN_MODE==='switch'){
  const selected=process.env.RELAY_SELECTED_MODEL; env.ANTHROPIC_MODEL=selected;
  const aliases={sonnet:'ANTHROPIC_DEFAULT_SONNET_MODEL',opus:'ANTHROPIC_DEFAULT_OPUS_MODEL',haiku:'ANTHROPIC_DEFAULT_HAIKU_MODEL'};
  const family=Object.keys(aliases).find(name=>selected.toLowerCase().includes(name));
  if(family) env[aliases[family]]=selected;
}
const cacheModels=models.map(model=>{const item={id:model.id,display_name:model.display_name||model.id};if(model.owned_by)item.owned_by=model.owned_by;if(model.context_window)item.context_window=model.context_window;return item;});
fs.writeFileSync(settingsOut,JSON.stringify(settings,null,2)+'\n');
fs.writeFileSync(cacheOut,JSON.stringify({baseUrl:process.env.RELAY_BASE_URL,fetchedAt:Date.now(),models:cacheModels},null,2)+'\n');
NODE
}

ensure_target_os
require_node
manual_sources=0
[ "$MODELS_ARG_SET" -eq 0 ] || manual_sources=$((manual_sources + 1))
[ "$MODELS_FILE_SET" -eq 0 ] || manual_sources=$((manual_sources + 1))
[ "$MANUAL" -eq 0 ] || manual_sources=$((manual_sources + 1))
[ "$manual_sources" -le 1 ] || die "Use only one manual source: --models, --models-file, or --manual"
[ "$LIST_MODELS" -eq 0 ] || MODE="list"
[ -z "$MODEL" ] || MODE="switch"
read_settings
configured_base="$(json_field "$SETTINGS_STATE" baseUrl)"
current_model="$(json_field "$SETTINGS_STATE" model)"
resolved_base="${BASE_URL_ARG:-${configured_base:-$DEFAULT_BASE_URL}}"

if [ "$MODELS_ARG_SET" -eq 1 ]; then normalize_models direct "$MODELS_ARG"
elif [ "$MODELS_FILE_SET" -eq 1 ]; then [ -f "$MODELS_FILE" ] || die "Models file not found: $MODELS_FILE"; normalize_models file "$MODELS_FILE"
elif [ "$MANUAL" -eq 1 ]; then read_manual_models
else
  resolved_key="${API_KEY_ARG:-$(json_field "$SETTINGS_STATE" apiKey)}"
  if [ -z "$resolved_key" ]; then [ -t 0 ] || die "No API key found; pass --api-key"; printf 'Paste relay API key: ' >&2; IFS= read -rs resolved_key; printf '\n' >&2; [ -n "$resolved_key" ] || die "API key cannot be empty"; fi
  resolved_auth="$AUTH_MODE"; [ "$resolved_auth" = "auto" ] && resolved_auth="$(json_field "$SETTINGS_STATE" authMode)"
  fetch_models "$resolved_base" "$resolved_key" "$resolved_auth"
fi

model_count="$(node -e "process.stdout.write(String(require(process.argv[1]).length))" "$MODELS_JSON")"
log "Resolved $model_count model(s)."
if [ "$MODE" = "list" ]; then show_models; exit 0; fi
selected_model=""
[ "$MODE" != "switch" ] || selected_model="$(select_model "$current_model")"
generate_settings_and_cache "$MODE" "$selected_model" "$resolved_base"
if [ "$DRY_RUN" -eq 1 ]; then log "Dry run: would update $SETTINGS_PATH and $CACHE_PATH."; [ -z "$selected_model" ] || log "Dry run: would switch default model to $selected_model."; exit 0; fi
backup_file "$SETTINGS_PATH"
backup_file "$CACHE_PATH"
atomic_copy "$WORK_DIR/settings.out.json" "$SETTINGS_PATH"
atomic_copy "$WORK_DIR/cache.out.json" "$CACHE_PATH"
log "Gateway discovery enabled: $DISCOVERY_KEY=1"
log "Compatibility cache updated: $CACHE_PATH"
if [ -n "$selected_model" ]; then log "Default model updated to: $selected_model"; else log "Current default model unchanged: ${current_model:-<unset>}"; fi
log "Restart Claude Code or the VS Code Claude Code extension to reload the model list."
