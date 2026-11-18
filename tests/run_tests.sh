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
export NI_IFCONFIG=$ROOT/tests/mocks/ifconfig NI_CURL=$ROOT/tests/mocks/curl NI_OPEN=$ROOT/tests/mocks/open
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

# ==== TASK2 ====

print "\n$pass passed, $fail failed"
(( fail == 0 ))
