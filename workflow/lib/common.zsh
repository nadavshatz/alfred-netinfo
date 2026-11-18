# lib/common.zsh — shared helpers for Network Info.
#
# Alfred Script Filter JSON helpers and network interface discovery.
# System tools are reached through NI_* variables so the test-suite can
# substitute mocks; nothing here ever passes a string to eval or sh -c.

zmodload zsh/datetime   # EPOCHSECONDS (updater)
setopt extended_glob no_unset pipe_fail

typeset -r NI_LABEL="io.github.nadavshatz.netinfo"
typeset -r NI_WF_DIR="${${(%):-%x}:A:h:h}"          # .../workflow

typeset -r NETWORKSETUP="${NI_NETWORKSETUP:-/usr/sbin/networksetup}"
typeset -r IPCONFIG="${NI_IPCONFIG:-/usr/sbin/ipconfig}"

# Updater (lib/update.zsh)
typeset -r UPD_LABEL=$NI_LABEL UPD_NAME="Network Info" UPD_PKG="Network-Info" UPD_WF_DIR=$NI_WF_DIR
typeset -r UPD_REPO="${NI_UPDATE_REPO:-https://github.com/nadavshatz/alfred-netinfo}"
typeset -r UPD_CURL="${NI_CURL:-/usr/bin/curl}" UPD_OPEN="${NI_OPEN:-/usr/bin/open}"

# ---------------------------------------------------------------------------
# Alfred JSON
# ---------------------------------------------------------------------------
typeset -ga ITEMS=()

js() {  # JSON string literal
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//[[:cntrl:]]/}
  print -rn -- "\"$s\""
}

# item TITLE SUBTITLE ARG VALID ICON [VARS_JSON]
# Valid items get a ⌘ modifier that carries the same arg (copy, not paste).
# VARS_JSON, if given, is a raw JSON object set as the item's "variables".
item() {
  local t=$1 sub=$2 arg=$3 valid=$4 icon=$5 vars=${6:-}
  local j="{\"title\":$(js "$t"),\"subtitle\":$(js "$sub"),\"arg\":$(js "$arg"),\"valid\":$valid"
  j+=",\"icon\":{\"path\":$(js "icons/$icon.png")}"
  [[ $valid == true && -z $vars ]] && j+=",\"mods\":{\"cmd\":{\"arg\":$(js "$arg"),\"subtitle\":\"Copy to clipboard\",\"valid\":true}}"
  [[ -n $vars ]] && j+=",\"variables\":$vars"
  ITEMS+=("$j}")
}

emit() { print -r -- "{\"skipknowledge\":true,\"items\":[${(j:,:)ITEMS}]}" }

# ---------------------------------------------------------------------------
# Interfaces
# ---------------------------------------------------------------------------

# A BSD interface name: letters then digits (en0, bridge0, utun12).
valid_device() { [[ ${1:-} == [a-z]##[0-9]# ]] }

# list_ports → PORTS=("<hardware port>\t<device>" ...) in service order.
typeset -ga PORTS=()
list_ports() {
  PORTS=()
  local line
  $NETWORKSETUP -listnetworkserviceorder 2>/dev/null | while IFS= read -r line; do
    [[ $line == (#b)'(Hardware Port: '(*)', Device: '([^\)]#)')' ]] || continue
    valid_device "$match[2]" || continue
    PORTS+=("$match[1]"$'\t'"$match[2]")
  done
}
