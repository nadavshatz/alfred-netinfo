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
typeset -r SUB="↩ paste · ⌘↩ copy"

# valid_ip STR: a bare IPv4 dotted quad (each octet 0–255) or IPv6 address.
valid_ip() {
  local s=${1:-} o
  if [[ $s == <0-255>.<0-255>.<0-255>.<0-255> ]]; then
    for o in ${(s:.:)s}; do [[ $o == (0|[1-9][0-9]#) ]] || return 1; done
    return 0
  fi
  [[ $s == [0-9a-fA-F:]## && $s == *:*:* && ${#s} -le 45 ]]
}

# external_ip → REPLY=validated address; returns 1 on any failure.
external_ip() {
  REPLY=
  local out
  out=$($CURL --proto '=https' --tlsv1.2 -fsS --max-time 3 -- "$EXT_URL" 2>/dev/null) || return 1
  out=${out%%[[:space:]]#}
  valid_ip "$out" || return 1
  REPLY=$out
}

port_icon() { [[ $1 == (Wi-Fi|AirPort)* ]] && print wifi || print lan }

do_ip() {
  if [[ $EXT_URL != https://[^[:space:]]## ]]; then
    item "External IP service must use https://" "Fix it in the workflow's configuration" "" false warning
  elif external_ip; then
    item "External IP: $REPLY" "$SUB" "$REPLY" true globe
  else
    item "External IP unavailable" "Offline, or $EXT_URL did not return an address" "" false warning
  fi
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
