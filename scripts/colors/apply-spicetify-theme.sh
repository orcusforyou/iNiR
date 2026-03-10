#!/usr/bin/env bash
#
# apply-spicetify-theme.sh - Generate and apply Spicetify color scheme
# from iNiR Material colors using custom theme with live updates.
#
# Design:
# - First run (Spotify not running): apply theme, start watch mode, launch Spotify
# - Subsequent runs (watch running): just update color.ini, watch handles live reload
# - No Spotify restarts on wallpaper change when watch mode is active
#
# Reads: ~/.local/state/quickshell/user/generated/colors.json
# Writes: ~/.config/spicetify/Themes/Inir/color.ini

set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────────────────────

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_DIR="$XDG_STATE_HOME/quickshell"
COLORS_JSON="$STATE_DIR/user/generated/colors.json"
LOG_FILE="$STATE_DIR/user/generated/spicetify_theme.log"
WATCH_LOCK="$STATE_DIR/user/generated/spicetify_watch.lock"

THEME_NAME="Inir"
SCHEME_NAME="matugen"
SLEEK_CSS_URL="https://raw.githubusercontent.com/spicetify/spicetify-themes/master/Sleek/user.css"

# Global associative array for colors
declare -A COLORS

# ─── Setup directories and logging ─────────────────────────────────────────────

mkdir -p "$STATE_DIR/user/generated" 2>/dev/null || true

if ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="/tmp/spicetify_theme_$$.log"
  touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
fi

log() {
  local timestamp
  timestamp=$(date '+%H:%M:%S')
  printf "[%s] [spicetify] %s\n" "$timestamp" "$*" >> "$LOG_FILE"
}

# ─── Helper functions ───────────────────────────────────────────────────────────

strip_hash() {
  local color="${1#\#}"
  echo "${color,,}"
}

get_spicetify_config_path() {
  local config_path="${SPICETIFY_CONFIG_PATH:-$XDG_CONFIG_HOME/spicetify/config-xpui.ini}"
  local cmd_config
  if cmd_config=$(spicetify -c 2>/dev/null) && [[ -n "$cmd_config" ]]; then
    config_path="$cmd_config"
  fi
  echo "$config_path"
}

is_process_running() {
  pgrep -x "$1" >/dev/null 2>&1
}

is_watch_active() {
  [[ -f "$WATCH_LOCK" ]] || pgrep -f "spicetify watch" >/dev/null 2>&1
}

acquire_watch_lock() {
  echo $$ > "$WATCH_LOCK"
}

release_watch_lock() {
  rm -f "$WATCH_LOCK" 2>/dev/null || true
}

# ─── Color extraction ───────────────────────────────────────────────────────────

read_colors() {
  if [[ ! -f "$COLORS_JSON" ]]; then
    log "colors.json not found at $COLORS_JSON"
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    log "jq not available"
    return 1
  fi

  COLORS[primary]=$(jq -r '.primary // "#8caaee"' "$COLORS_JSON")
  COLORS[on_surface]=$(jq -r '.on_surface // "#dce0e8"' "$COLORS_JSON")
  COLORS[on_surface_variant]=$(jq -r '.on_surface_variant // "#a6adc8"' "$COLORS_JSON")
  COLORS[surface]=$(jq -r '.surface // "#1e1e2e"' "$COLORS_JSON")
  COLORS[surface_container_low]=$(jq -r '.surface_container_low // "#181825"' "$COLORS_JSON")
  COLORS[surface_container]=$(jq -r '.surface_container // "#313244"' "$COLORS_JSON")
  COLORS[surface_container_high]=$(jq -r '.surface_container_high // "#45475a"' "$COLORS_JSON")
  COLORS[primary_container]=$(jq -r '.primary_container // "#313244"' "$COLORS_JSON")
  COLORS[secondary]=$(jq -r '.secondary // "#89b4fa"' "$COLORS_JSON")
  COLORS[tertiary]=$(jq -r '.tertiary // "#94e2d5"' "$COLORS_JSON")
  COLORS[outline]=$(jq -r '.outline // "#585b70"' "$COLORS_JSON")
  COLORS[outline_variant]=$(jq -r '.outline_variant // "#45475a"' "$COLORS_JSON")
  COLORS[error]=$(jq -r '.error // "#f38ba8"' "$COLORS_JSON")
  COLORS[shadow]=$(jq -r '.shadow // "#000000"' "$COLORS_JSON")
}

# ─── Theme generation ───────────────────────────────────────────────────────────

generate_color_ini() {
  local color_file="$1"
  
  read_colors || return 1

  cat > "$color_file" << EOF
[${SCHEME_NAME}]
text               = $(strip_hash "${COLORS[on_surface]}")
subtext            = $(strip_hash "${COLORS[on_surface_variant]}")
main               = $(strip_hash "${COLORS[surface]}")
sidebar            = $(strip_hash "${COLORS[surface_container_low]}")
player             = $(strip_hash "${COLORS[surface_container]}")
card               = $(strip_hash "${COLORS[surface_container_high]}")
shadow             = $(strip_hash "${COLORS[shadow]}")
selected-row       = $(strip_hash "${COLORS[primary_container]}")
button             = $(strip_hash "${COLORS[primary]}")
button-active      = $(strip_hash "${COLORS[secondary]}")
button-disabled    = $(strip_hash "${COLORS[outline]}")
tab-active         = $(strip_hash "${COLORS[primary_container]}")
notification       = $(strip_hash "${COLORS[tertiary]}")
notification-error = $(strip_hash "${COLORS[error]}")
misc               = $(strip_hash "${COLORS[outline_variant]}")
EOF
}

download_sleek_css() {
  local css_file="$1"
  if [[ ! -f "$css_file" ]]; then
    log "Downloading base CSS from Sleek theme..."
    if curl -L --create-dirs -o "$css_file" "$SLEEK_CSS_URL" 2>/dev/null; then
      log "Downloaded base CSS"
    else
      log "Warning: Failed to download base CSS"
    fi
  fi
}

# ─── Spicetify operations ──────────────────────────────────────────────────────

configure_spicetify() {
  local theme_dir="$1"
  local color_file="$theme_dir/color.ini"
  local user_css="$theme_dir/user.css"

  mkdir -p "$theme_dir" 2>/dev/null || return 1
  download_sleek_css "$user_css"
  generate_color_ini "$color_file" || return 1

  spicetify config inject_css 1 replace_colors 1 >> "$LOG_FILE" 2>&1 || true
  spicetify config current_theme "$THEME_NAME" color_scheme "$SCHEME_NAME" >> "$LOG_FILE" 2>&1 || true
}

apply_spicetify_theme() {
  local apply_out
  if apply_out=$(spicetify apply 2>&1); then
    printf "%s\n" "$apply_out" >> "$LOG_FILE" 2>&1
    return 0
  fi

  printf "%s\n" "$apply_out" >> "$LOG_FILE" 2>&1

  if printf "%s" "$apply_out" | grep -Eqi "backup|cannot find backup"; then
    log "Running spicetify backup apply..."
    local backup_out
    if backup_out=$(spicetify backup apply 2>&1); then
      printf "%s\n" "$backup_out" >> "$LOG_FILE" 2>&1
      return 0
    fi
    printf "%s\n" "$backup_out" >> "$LOG_FILE" 2>&1
    return 1
  fi

  return 1
}

start_watch_mode() {
  log "Starting spicetify watch mode..."
  nohup spicetify watch -s >> "$LOG_FILE" 2>&1 &
  local watch_pid=$!
  sleep 0.5

  if kill -0 "$watch_pid" 2>/dev/null; then
    acquire_watch_lock
    log "Watch mode started (PID: $watch_pid)"
    return 0
  else
    log "Failed to start watch mode"
    release_watch_lock
    return 1
  fi
}

# ─── Main logic ────────────────────────────────────────────────────────────────

main() {
  if ! command -v spicetify &>/dev/null; then
    log "spicetify not installed, skipping"
    exit 0
  fi

  local spicetify_config
  spicetify_config=$(get_spicetify_config_path)
  local spicetify_root
  spicetify_root="$(dirname "$spicetify_config")"
  local theme_dir="$spicetify_root/Themes/$THEME_NAME"

  configure_spicetify "$theme_dir" || {
    log "Failed to configure spicetify"
    exit 1
  }

  local spotify_running=false
  local watch_running=false

  is_process_running "spotify" && spotify_running=true
  is_watch_active && watch_running=true

  if $watch_running; then
    log "Watch mode active - colors updated (live reload)"
    exit 0
  fi

  if ! $spotify_running; then
    log "Spotify not running - applying theme and starting watch mode"
    apply_spicetify_theme || {
      log "Failed to apply theme"
      exit 1
    }
    log "Theme applied: $THEME_NAME/$SCHEME_NAME"
    start_watch_mode
  else
    log "Spotify running without watch - starting watch mode (no restart)"
    start_watch_mode || {
      log "Watch start failed, colors will apply on next Spotify launch"
    }
  fi

  exit 0
}

main "$@"
