#!/bin/zsh -f
# netinfo.sh — Network Info Script Filter.
#
#   netinfo.sh ip     external IP (HTTPS) + local IP per interface
#   netinfo.sh mac    MAC address per hardware port

source "${0:A:h}/lib/common.zsh"
typeset -i HAS_UPDATER=0
[[ -r $NI_WF_DIR/lib/update.zsh ]] && source $NI_WF_DIR/lib/update.zsh && HAS_UPDATER=1

typeset -r CURL="${NI_CURL:-/usr/bin/curl}"
typeset -r EXT_URL="${ext_ip_url:-https://api.ipify.org}"
typeset -r EXT6_URL="${ext_ip6_url-https://api6.ipify.org}"   # empty = off
typeset -r SUB="↩ paste · ⌘↩ copy"

# valid_ip STR: a bare IPv4 dotted quad (each octet 0–255) or IPv6 address.
valid_ip() {
  local s=${1:-} o
  if [[ $s == <0-255>.<0-255>.<0-255>.<0-255> ]]; then
    for o in ${(s:.:)s}; do [[ $o == (0|[1-9][0-9]#) ]] || return 1; done
    return 0
  fi
  valid_ipv6 "$s"
}

# valid_ipv6 STR: 8 groups of 1–4 hex digits, or fewer around exactly one "::".
valid_ipv6() {
  local s=$1 g
  [[ $s == [0-9a-fA-F:]## && ${#s} -le 39 && $s == *:* ]] || return 1
  local -a groups
  if [[ $s == *::* ]]; then
    [[ $s == *::*::* ]] && return 1
    local l=${s%%::*} r=${s#*::}
    [[ -n $l ]] && groups+=("${(@s.:.)l}")
    [[ -n $r ]] && groups+=("${(@s.:.)r}")
    (( $#groups <= 7 )) || return 1
  else
    groups=("${(@s.:.)s}")
    (( $#groups == 8 )) || return 1
  fi
  for g in "${groups[@]}"; do [[ $g == [0-9a-fA-F](#c1,4) ]] || return 1; done
  return 0
}

# fetch_ip -4|-6 URL → prints the response body; non-zero on failure.
fetch_ip() { $CURL -q $1 --proto '=https' --tlsv1.2 -fsS --max-time 3 -- "$2" 2>/dev/null }

valid_url() { [[ $1 == https://[^[:space:]]## ]] }

port_icon() { [[ $1 == (Wi-Fi|AirPort)* ]] && print wifi || print lan }

do_ip() {
  # IPv6 lookup runs in the background so being offline costs 3 s, not 6.
  local v6file= v6pid=
  if [[ -n $EXT6_URL ]] && valid_url "$EXT6_URL"; then
    v6file=$(mktemp) && { fetch_ip -6 "$EXT6_URL" > $v6file & v6pid=$! }
  fi
  local out
  if ! valid_url "$EXT_URL"; then
    item "External IP service must use https://" "Fix it in the workflow's configuration" "" false warning
  elif out=$(fetch_ip -4 "$EXT_URL") && out=${out%%[[:space:]]#} && valid_ip "$out"; then
    item "External IP: $out" "$SUB" "$out" true globe
  else
    item "External IP unavailable" "Offline, or $EXT_URL did not return an address" "" false warning
  fi
  if [[ -n $EXT6_URL ]] && ! valid_url "$EXT6_URL"; then
    item "External IPv6 service must use https://" "Fix it in the workflow's configuration, or leave it empty" "" false warning
  elif [[ -n $v6pid ]]; then
    # No IPv6 is normal on many networks, so failure adds no item.
    wait $v6pid 2>/dev/null
    out=$(<$v6file); out=${out%%[[:space:]]#}
    [[ $out == *:* ]] && valid_ipv6 "$out" && item "External IPv6: $out" "$SUB" "$out" true globe
  fi
  [[ -n $v6file ]] && rm -f -- $v6file
  list_ports
  local p name dev addr
  for p in $PORTS; do
    name=${p%%$'\t'*} dev=${p#*$'\t'}
    addr=$($IPCONFIG getifaddr "$dev" 2>/dev/null) || continue
    valid_ip "$addr" || continue
    item "$name ($dev): $addr" "$SUB" "$addr" true $(port_icon "$name")
  done
  (( HAS_UPDATER )) && update_notice "$NI_WF_DIR/action.sh"
}

do_mac() {
  list_ports
  # networksetup reports the hardware address; ifconfig shows the private
  # placeholder 02:00:00:00:00:00 to unprivileged processes on recent macOS.
  local p name dev out
  for p in $PORTS; do
    name=${p%%$'\t'*} dev=${p#*$'\t'}
    out=$($NETWORKSETUP -getmacaddress "$dev" 2>/dev/null) || continue
    [[ $out == (#b)'Ethernet Address: '([0-9a-fA-F:](#c17))' '* ]] || continue
    [[ $match[1] == 02:00:00:00:00:00 ]] && continue
    item "$name ($dev) MAC: $match[1]" "$SUB" "$match[1]" true mac
  done
  (( $#ITEMS )) || item "No MAC addresses found" "networksetup lists no hardware port with a MAC address" "" false warning
}

case ${1:-} in
  ip)  do_ip ;;
  mac) do_mac ;;
  *)   print -u2 "usage: netinfo.sh ip|mac"; exit 64 ;;
esac
emit
