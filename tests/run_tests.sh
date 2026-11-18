#!/bin/zsh -f
# Network Info test-suite. Runs on macOS or Linux with zsh + jq; every system
# tool is mocked (tests/mocks) and nothing touches the network.
#
#   zsh tests/run_tests.sh

setopt extended_glob no_unset
ROOT=${0:A:h:h}
WF=$ROOT/workflow
SANDBOX=$(mktemp -d)
trap 'rm -rf $SANDBOX' EXIT

export MOCK_DIR=$SANDBOX/mock
export NI_NETWORKSETUP=$ROOT/tests/mocks/networksetup NI_IPCONFIG=$ROOT/tests/mocks/ipconfig
export NI_CURL=$ROOT/tests/mocks/curl NI_OPEN=$ROOT/tests/mocks/open
export alfred_workflow_cache=$SANDBOX/cache alfred_workflow_data=$SANDBOX/data
export alfred_workflow_version=1.0.0 update_mode=off
mkdir -p $MOCK_DIR

integer pass=0 fail=0
ok()   { print -P "%F{green}✔%f $1"; (( ++pass )) }
bad()  { print -P "%F{red}✘ $1%f"; [[ -n ${2:-} ]] && print -r -- "   $2"; (( ++fail )) }
check() { local d=$1; shift; if "$@"; then ok $d; else bad $d; fi }
reset_mocks() { rm -rf $MOCK_DIR; mkdir -p $MOCK_DIR }

ni() { $WF/netinfo.sh "$@" }
titles() { ni "$@" | jq -r '.items[].title' }

# --- unit: helpers -------------------------------------------------------------
(
  source $WF/lib/common.zsh
  [[ $(js $'a"b\\c\n\td') == '"a\"b\\c\n\td"' ]] && print ok || print "bad js: $(js $'a"b\\c\n\td')"
) | read -r r
[[ $r == ok ]] && ok "js escapes quotes, backslashes, newlines, tabs" || bad "js" "$r"

(
  source $WF/lib/common.zsh
  list_ports
  print -r -- ${#PORTS}
  print -rl -- $PORTS
) > $SANDBOX/ports.out
check "list_ports finds 3 ports (skips port with empty device)" eval '[[ $(head -1 $SANDBOX/ports.out) == 3 ]]'
check "list_ports keeps names with spaces and slashes" \
  eval '[[ $(<$SANDBOX/ports.out) == *$'"'"'USB 10/100/1000 LAN\ten7'"'"'* ]]'

(
  source $WF/lib/common.zsh
  item 'T "q"' sub arg true wifi
  item T2 sub2 arg2 false lan
  emit
) > $SANDBOX/emit.out
check "emit produces valid JSON" eval 'jq -e . $SANDBOX/emit.out >/dev/null'
check "item fields + cmd copy modifier" \
  eval '[[ $(jq -r ".items[0] | [.title,.arg,.valid,.icon.path,.mods.cmd.arg] | @tsv" $SANDBOX/emit.out) == "T \"q\"	arg	true	icons/wifi.png	arg" ]]'
check "invalid item has valid:false" eval '[[ $(jq -r ".items[1].valid" $SANDBOX/emit.out) == false ]]'

valid_dev() { ( source $WF/lib/common.zsh; valid_device "$1" ) }
check "valid_device accepts en0, bridge0, utun12" eval 'valid_dev en0 && valid_dev bridge0 && valid_dev utun12'
check "valid_device rejects '-a', 'en0;x', '', 'en 0'" \
  eval '! valid_dev -a && ! valid_dev "en0;x" && ! valid_dev "" && ! valid_dev "en 0"'

# --- ip ------------------------------------------------------------------------
reset_mocks
print 192.168.1.5 > $MOCK_DIR/ip_en0
print 203.0.113.7 > $MOCK_DIR/ext
out=$(ni ip)
check "ip emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
t=$(print -r -- $out | jq -r '.items[].title')
check "external IP is first" eval '[[ ${${(f)t}[1]} == "External IP: 203.0.113.7" ]]'
check "Wi-Fi local IP listed" eval '[[ ${${(f)t}[2]} == "Wi-Fi (en0): 192.168.1.5" ]]'
check "interfaces without an address are omitted" eval '[[ $(print -r -- $out | jq ".items|length") == 2 ]]'
check "local item arg is the bare IP" eval '[[ $(print -r -- $out | jq -r ".items[1].arg") == 192.168.1.5 ]]'
check "external IP fetched over https only, 3s timeout" \
  eval '[[ ${(j: :)${(f)"$(<$MOCK_DIR/curl.log)"}} == *"--proto =https"*"--max-time 3"*"https://api.ipify.org"* ]]'

reset_mocks; print 192.168.1.5 > $MOCK_DIR/ip_en0; touch $MOCK_DIR/offline
out=$(ni ip)
check "offline: external item says unavailable and is not actionable" \
  eval '[[ $(print -r -- $out | jq -r ".items[0] | [.title,.valid] | @tsv") == "External IP unavailable	false" ]]'
check "offline: local IP still listed" eval '[[ $(print -r -- $out | jq -r ".items[1].title") == "Wi-Fi (en0): 192.168.1.5" ]]'

reset_mocks; print '<html>pwned</html>' > $MOCK_DIR/ext
check "non-IP response is not displayed" eval '[[ $(titles ip | head -1) == "External IP unavailable" ]]'
reset_mocks; print '1.2.3.4; rm -rf ~' > $MOCK_DIR/ext
check "IP followed by junk is rejected" eval '[[ $(titles ip | head -1) == "External IP unavailable" ]]'
reset_mocks; print '2001:db8::1' > $MOCK_DIR/ext
check "IPv6 external address accepted" eval '[[ $(titles ip | head -1) == "External IP: 2001:db8::1" ]]'
reset_mocks; print '999.1.1.1' > $MOCK_DIR/ext
check "out-of-range IPv4 rejected" eval '[[ $(titles ip | head -1) == "External IP unavailable" ]]'

reset_mocks; print 203.0.113.7 > $MOCK_DIR/ext
out=$(ext_ip_url=http://api.ipify.org ni ip)
check "http:// service refused" eval '[[ $(print -r -- $out | jq -r ".items[0].title") == "External IP service must use https://" ]]'
check "http:// service: curl never called" eval '[[ ! -e $MOCK_DIR/curl.log ]]'
reset_mocks; print 203.0.113.7 > $MOCK_DIR/ext
out=$(ext_ip_url='https://x -o /tmp/p' ni ip)
check "URL with whitespace refused" eval '[[ $(print -r -- $out | jq -r ".items[0].title") == "External IP service must use https://" && ! -e $MOCK_DIR/curl.log ]]'

reset_mocks
print 'Evil, Device: en0)' > /dev/null
cat > $MOCK_DIR/ports <<'X'
(Hardware Port: Odd "Port" \ Name, Device: en3)
(Hardware Port: Injected, Device: en0;touch /tmp/x)
X
print 10.0.0.9 > $MOCK_DIR/ip_en3
out=$(ni ip)
check "odd port names are JSON-escaped" eval '[[ $(print -r -- $out | jq -r ".items[1].title") == "Odd \"Port\" \\ Name (en3): 10.0.0.9" ]]'
check "invalid device names never reach ipconfig" eval '[[ $(<$MOCK_DIR/calls.log) != *";"* ]]'

# --- mac -----------------------------------------------------------------------
reset_mocks
print aa:bb:cc:dd:ee:ff > $MOCK_DIR/mac_en0
print 00:11:22:33:44:55 > $MOCK_DIR/mac_en7
out=$(ni mac)
check "mac emits valid JSON" eval 'print -r -- $out | jq -e . >/dev/null'
check "mac lists ports in service order" \
  eval '[[ $(print -r -- $out | jq -r ".items[].title") == "USB 10/100/1000 LAN (en7) MAC: 00:11:22:33:44:55"$'"'"'\n'"'"'"Wi-Fi (en0) MAC: aa:bb:cc:dd:ee:ff" ]]'
check "mac arg is the bare address" eval '[[ $(print -r -- $out | jq -r ".items[1].arg") == aa:bb:cc:dd:ee:ff ]]'
check "mac never calls curl" eval '[[ ! -e $MOCK_DIR/curl.log ]]'
reset_mocks; print 02:00:00:00:00:00 > $MOCK_DIR/mac_bridge0; print aa:bb:cc:dd:ee:ff > $MOCK_DIR/mac_en0
check "privacy placeholder 02:00:00:00:00:00 is hidden" eval '[[ $(titles mac) == "Wi-Fi (en0) MAC: aa:bb:cc:dd:ee:ff" ]]'
check "mac uses networksetup -getmacaddress, not ifconfig" eval '[[ $(<$MOCK_DIR/calls.log) == *"networksetup -getmacaddress en0"* && $(<$MOCK_DIR/calls.log) != *ifconfig* ]]'
reset_mocks
check "no MACs → explanatory invalid item" eval '[[ $(ni mac | jq -r ".items[0] | [.title,.valid] | @tsv") == "No MAC addresses found	false" ]]'
reset_mocks
check "unknown mode exits non-zero" eval '! ni bogus >/dev/null 2>&1'

# --- updates -------------------------------------------------------------------
reset_mocks
export alfred_workflow_version=1.0.0
action() { $WF/action.sh "$*" }
wait_for() { integer i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.1; done; return 1 }
(
  source $WF/lib/common.zsh; source $WF/lib/update.zsh
  for spec in "1.2.0 1.1.0" "1.10.0 1.9.9" "1.2.0 1.2.0-beta"; do version_gt ${=spec} || exit 1; done
  for spec in "1.1.0 1.1.0" "1.0.9 1.1.0" "1.2.0-beta 1.2.0"; do version_gt ${=spec} && exit 1; done
  exit 0
) && ok "version_gt ordering" || bad "version_gt ordering"
UPD=$alfred_workflow_cache/update
mkpkg() {  # version → a fake GitHub release containing a real build
  zsh $ROOT/scripts/build.sh $1 >/dev/null
  mkdir -p $MOCK_DIR/releases/v$1
  mv -f $ROOT/dist/Network-Info-$1.alfredworkflow $ROOT/dist/Network-Info-$1.alfredworkflow.sha256 $MOCK_DIR/releases/v$1/
}
mkpkg 9.0.0
print 9.0.0 > $MOCK_DIR/latest
rm -f $UPD
update_mode=notify ni ip >/dev/null
check "ip starts a background update check" wait_for '[[ $(cat $UPD 2>/dev/null) == "9.0.0 "* ]]'
out=$(update_mode=notify ni ip)
check "newer release announced in ip results" eval '[[ $(print -r -- $out | jq -r ".items[-1].title") == "Update available: Network Info 9.0.0" ]]'
check "update item routes to the action via variables" \
  eval '[[ $(print -r -- $out | jq -r ".items[-1] | [.arg, .variables.action] | @tsv") == "update_install 9.0.0	update" ]]'
check "update_mode=off hides the notice" eval '[[ $(update_mode=off titles ip) != *"Update available"* ]]'
check "mac never shows update items" eval '[[ $(update_mode=notify titles mac) != *"Update available"* ]]'
check "manual check: newer available" eval '[[ $(action update_check now) == "Network Info 9.0.0 is available (you have 1.0.0)" ]]'
msg=$(action update_install 9.0.0)
check "install downloads, verifies and opens in Alfred" \
  eval '[[ $msg == "Opening Network Info 9.0.0. Confirm the update in Alfred" && $(<$MOCK_DIR/open.log) == $alfred_workflow_cache/Network-Info-9.0.0.alfredworkflow ]]'
print "0000000000000000000000000000000000000000000000000000000000000000  x" > $MOCK_DIR/releases/v9.0.0/Network-Info-9.0.0.alfredworkflow.sha256
rm -f $MOCK_DIR/open.log
check "tampered download is rejected" eval '[[ $(action update_install 9.0.0) == "Update not installed: checksum mismatch" && ! -e $MOCK_DIR/open.log ]]'
check "invalid version argument is rejected" eval '[[ $(action update_install "1.x") == "Invalid version: 1.x" ]]'
check "unknown action is refused" eval '[[ $(action "rm -rf /") == "Unknown action" ]]'
touch $MOCK_DIR/offline
check "manual check offline reports it" eval '[[ $(action update_check now) == "Could not reach GitHub to check for updates" ]]'
check "update requests are https-only" eval '[[ $(<$MOCK_DIR/curl.log) == *"=https"* ]]'

print "\n$pass passed, $fail failed"
(( fail == 0 ))
