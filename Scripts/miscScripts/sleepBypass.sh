#!/bin/bash
# Keep Awake — swiftDialog select list + caffeinate (robust text parsing)
# - Visible 5-min timeout (reliable across versions)
# - Trusts exit code 0 for "Start"
# - Parses SelectedOption (quoted/unquoted), falls back to SelectedIndex or Duration
# - Launches caffeinate -di asynchronously; records PID

set -euo pipefail

PIDFILE="/var/tmp/com.company.sleepblocker.caffeinate.pid"
DEBUG_TXT="/var/tmp/sleepblocker_last_dialog.txt"

# ----- Locate swiftDialog (install if missing) -----
DIALOG_CLI="/usr/local/bin/dialog"
DIALOG_APP_CLI="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/dialogcli"
DIALOG_APP_OLD="/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/dialog"

install_swiftdialog() {
  local url="https://github.com/swiftDialog/swiftDialog/releases/latest/download/dialog.pkg"
  local pkg="/var/tmp/swiftdialog.pkg"
  /usr/bin/curl -fsSL "$url" -o "$pkg" || return 1
  /usr/sbin/installer -pkg "$pkg" -target / >/dev/null 2>&1 || return 1
  /bin/rm -f "$pkg" || true
}

if [[ -x "$DIALOG_CLI" ]]; then
  DIALOG_BIN="$DIALOG_CLI"
elif [[ -x "$DIALOG_APP_CLI" ]]; then
  DIALOG_BIN="$DIALOG_APP_CLI"
elif [[ -x "$DIALOG_APP_OLD" ]]; then
  DIALOG_BIN="$DIALOG_APP_OLD"
else
  echo "swiftDialog not found; attempting install..."
  if install_swiftdialog; then
    if [[ -x "$DIALOG_CLI" ]]; then
      DIALOG_BIN="$DIALOG_CLI"
    elif [[ -x "$DIALOG_APP_CLI" ]]; then
      DIALOG_BIN="$DIALOG_APP_CLI"
    elif [[ -x "$DIALOG_APP_OLD" ]]; then
      DIALOG_BIN="$DIALOG_APP_OLD"
    else
      echo "swiftDialog install appears to have failed; exiting quietly."
      exit 0
    fi
  else
    echo "swiftDialog download/install failed; exiting quietly."
    exit 0
  fi
fi

# ----- Console user + runner -----
get_console_user() {
  /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" \
  | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]+:/ { if ($2 != "loginwindow") print $2 }'
}
run_as_user() {
  local uid; uid=$(/usr/bin/id -u "$CONSOLE_USER")
  /bin/launchctl asuser "$uid" /usr/bin/env PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$@"
}
CONSOLE_USER="$(get_console_user || true)"
if [[ -z "${CONSOLE_USER}" ]]; then
  echo "No logged-in user; nothing to do."
  exit 0
fi

# ----- Selection dialog (text output, visible timer) -----
selection_out="$(
  run_as_user "$DIALOG_BIN" \
    --title "Keep Mac Awake" \
    --message "Choose how long to prevent sleep. This prompt auto-closes after 5 minutes if no choice is made." \
    --icon "SF=bolt.fill" \
    --width 520 --height 280 --alignment center --centericon --moveable \
    --selecttitle "Duration" \
    --selectitems "30 minutes,1 hour,2 hours,3 hours" \
    --selectdefault "1 hour" \
    --button1text "Start" --button2text "Cancel" \
    --timer 300 \
    2>/dev/null
)"
dialog_rc=$?

# Save raw output for troubleshooting (this is what we parse)
printf '%s\n' "$selection_out" > "$DEBUG_TXT" 2>/dev/null || true

# Only proceed if Button 1 was pressed (exit code 0). Others (cancel/timeout) exit quietly.
if [[ $dialog_rc -ne 0 ]]; then
  echo "No selection (swiftDialog exit code: $dialog_rc)."
  exit 0
fi

# ----- Extract the selected option (handle quotes/spacing) -----
SELECTED_OPTION=""
# Try SelectedOption
sel_line="$(printf '%s\n' "$selection_out" | /usr/bin/grep -i '^[[:space:]]*"*SelectedOption"*[[:space:]]*:' | /usr/bin/head -n1 || true)"
if [[ -n "$sel_line" ]]; then
  val="$(printf '%s' "$sel_line" | /usr/bin/sed -E 's/^[^:]*:[[:space:]]*//')"
  # Trim surrounding quotes and whitespace
  val="${val%\"}"; val="${val#\"}"; val="$(printf '%s' "$val" | /usr/bin/sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  SELECTED_OPTION="$val"
fi

# Fallback: SelectedIndex → map to our list
if [[ -z "$SELECTED_OPTION" ]]; then
  idx_line="$(printf '%s\n' "$selection_out" | /usr/bin/grep -i '^[[:space:]]*"*SelectedIndex"*[[:space:]]*:' | /usr/bin/head -n1 || true)"
  if [[ -n "$idx_line" ]]; then
    idx_val="$(printf '%s' "$idx_line" | /usr/bin/sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//; s/[[:space:]]+$//')"
    case "$idx_val" in
      0) SELECTED_OPTION="30 minutes" ;;
      1) SELECTED_OPTION="1 hour" ;;
      2) SELECTED_OPTION="2 hours" ;;
      3) SELECTED_OPTION="3 hours" ;;
    esac
  fi
fi

# Fallback: Duration (some builds echo the field label)
if [[ -z "$SELECTED_OPTION" ]]; then
  dur_line="$(printf '%s\n' "$selection_out" | /usr/bin/grep -i '^[[:space:]]*"*Duration"*[[:space:]]*:' | /usr/bin/head -n1 || true)"
  if [[ -n "$dur_line" ]]; then
    val="$(printf '%s' "$dur_line" | /usr/bin/sed -E 's/^[^:]*:[[:space:]]*//')"
    val="${val%\"}"; val="${val#\"}"; val="$(printf '%s' "$val" | /usr/bin/sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    SELECTED_OPTION="$val"
  fi
fi

if [[ -z "$SELECTED_OPTION" ]]; then
  echo "Start pressed, but no parsable selection. See $DEBUG_TXT"
  exit 0
fi

# ----- Map selection to seconds -----
case "$SELECTED_OPTION" in
  "30 minutes") DURATION_SECONDS=1800 ;;
  "1 hour")     DURATION_SECONDS=3600 ;;
  "2 hours")    DURATION_SECONDS=7200 ;;
  "3 hours")    DURATION_SECONDS=10800 ;;
  *) echo "Unexpected selection text: $SELECTED_OPTION (see $DEBUG_TXT)"; exit 0 ;;
esac

# OPTIONAL: single-instance — uncomment to replace any prior session from this tool
# /usr/bin/pkill -f "^/usr/bin/caffeinate -di -t " || true

# ----- Launch caffeinate asynchronously (-di prevents idle + display sleep) -----
nohup /usr/bin/caffeinate -di -t "$DURATION_SECONDS" >/dev/null 2>&1 & disown
newpid=$! || true
[[ -n "${newpid}" ]] && echo "$newpid" > "$PIDFILE" 2>/dev/null || true

end_epoch=$(( $(/bin/date +%s) + DURATION_SECONDS ))
end_str="$(/bin/date -r "$end_epoch" '+%Y-%m-%d %H:%M:%S')"

echo "Started caffeinate pid=${newpid:-unknown} for $SELECTED_OPTION; ends around $end_str"
echo "Verify: pmset -g assertions | grep -A20 'Listed by owning process' | grep caffeinate"
exit 0