#!/bin/zsh -f
# Packaging test: the .alfredworkflow contains everything Alfred needs, keeps
# executable bits, carries the stamped version and a matching checksum.
setopt extended_glob no_unset
ROOT=${0:A:h:h}
integer fail=0
ok()  { print -P "%F{green}✔%f $1" }
bad() { print -P "%F{red}✘ $1%f"; (( ++fail )) }

out=$(zsh $ROOT/scripts/build.sh 9.8.7) || { print -r -- $out; exit 1 }
PKG=$ROOT/dist/Network-Info-9.8.7.alfredworkflow
[[ -f $PKG ]] && ok "package built" || bad "package missing"

X=$(mktemp -d); trap 'rm -rf $X' EXIT
(cd $X && unzip -q $PKG)
for f in info.plist icon.png netinfo.sh ip.sh mac.sh action.sh lib/common.zsh lib/update.zsh \
         icons/{globe,lan,wifi,mac,warning,update}.png; do
  [[ -f $X/$f ]] && ok "contains $f" || bad "missing $f"
done
for f in netinfo.sh ip.sh mac.sh action.sh; do
  [[ -x $X/$f ]] && ok "$f is executable" || bad "$f not executable"
done
vpat=$'*\n\t<key>version</key>\n\t<string>9.8.7</string>*'
[[ $(<$X/info.plist) == ${~vpat} ]] && ok "version stamped" || bad "version not stamped"
[[ $(<$ROOT/workflow/info.plist) != *9.8.7* ]] && ok "source tree untouched" || bad "source tree modified"
for p in $(cd $X && print -l -- **/*(.)); do
  [[ $p == (tests|scripts|docs)/* ]] && bad "dev file shipped: $p"
done
if [[ -x /usr/bin/shasum ]]; then got=$(/usr/bin/shasum -a 256 $PKG); else got=$(sha256sum $PKG); fi
[[ $(<$PKG.sha256) == "${got%% *}  ${PKG:t}" ]] && ok "checksum matches package" || bad "checksum does not match"
# Every script file the plist references must ship.
for s in ${(f)"$(grep -A1 '<key>scriptfile</key>' $X/info.plist | grep -o '[a-z_]*\.sh')"}; do
  [[ -x $X/$s ]] && ok "plist scriptfile $s ships" || bad "plist references missing $s"
done
zsh $ROOT/scripts/build.sh not-a-version >/dev/null 2>&1 && bad "bad version accepted" || ok "bad version rejected"
rm -f $PKG $PKG.sha256
(( fail == 0 )) && print "\nbuild: all passed"
(( fail == 0 ))
