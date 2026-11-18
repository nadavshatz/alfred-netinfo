# lib/update.zsh — update checks against GitHub Releases.
#
# Shared by nadavshatz Alfred workflows (adapted from Insomniac). The caller
# sets these before sourcing:
#   UPD_LABEL   bundle id               UPD_NAME   display name
#   UPD_PKG     package file prefix     UPD_REPO   https://github.com/<owner>/<repo>
#   UPD_WF_DIR  workflow directory      UPD_CURL / UPD_OPEN  tool paths
#
#   check    HEAD <repo>/releases/latest → 302 Location …/releases/tag/vX.Y.Z.
#            No API token, no JSON parsing. Result cached for 24h.
#   install  download <pkg>-X.Y.Z.alfredworkflow + .sha256 from the release,
#            verify the checksum, bundle id and version, then `open` it.
#            Alfred shows its own "update workflow" prompt and keeps settings.

zmodload zsh/datetime
typeset -r UPD_CACHE="${alfred_workflow_cache:-$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/$UPD_LABEL}"
typeset -r UPD_FILE="$UPD_CACHE/update"            # "<latest-version> <checked-epoch>"
typeset -r CFG_UPDATE="${update_mode:-notify}"     # notify | auto | off
typeset -ri UPD_INTERVAL=86400
typeset UPD_ERR=
[[ -d $UPD_CACHE ]] || mkdir -p -m 700 -- "$UPD_CACHE"

current_version() {
  if [[ -n ${alfred_workflow_version:-} ]]; then
    print -r -- $alfred_workflow_version; return
  fi
  local key=$'\n\t<key>version</key>\n\t<string>' p
  p=$(<$UPD_WF_DIR/info.plist)
  [[ $p == *$key* ]] || return 1
  p=${p#*$key}
  print -r -- ${p%%</string>*}
}

# version_gt A B: true if A is newer than B. Numeric X.Y.Z; a pre-release
# (1.2.0-beta) ranks below its release (1.2.0).
version_gt() {
  local a=${1#v} b=${2#v}
  local -a A=(${(s:.:)${a%%-*}}) B=(${(s:.:)${b%%-*}})
  integer i x y
  for i in 1 2 3; do
    x=${A[i]:-0} y=${B[i]:-0}
    (( x > y )) && return 0
    (( x < y )) && return 1
  done
  [[ $a != *-* && $b == *-* ]]
}

valid_version() { [[ $1 == <->.<->.<->(-[A-Za-z0-9.]##|) ]] }

# update_available → REPLY=newer version from the cache.
update_available() {
  REPLY=
  [[ $CFG_UPDATE == off || ! -r $UPD_FILE ]] && return 1
  local v t
  read -r v t < $UPD_FILE
  valid_version "${v:-}" || return 1
  version_gt $v "$(current_version)" || return 1
  REPLY=$v
}

# update_due: no check in the last 24h (and checks not switched off).
update_due() {
  [[ $CFG_UPDATE == off ]] && return 1
  [[ -r $UPD_FILE ]] || return 0
  local v t
  read -r v t < $UPD_FILE
  [[ ${t:-} == <-> ]] || return 0
  (( EPOCHSECONDS - t >= UPD_INTERVAL ))
}

update_mark_checked() {  # version
  print -r -- "$1 $EPOCHSECONDS" > $UPD_FILE.$$ && mv -f -- $UPD_FILE.$$ $UPD_FILE
}

# fetch_latest → REPLY=latest release version (network).
fetch_latest() {
  REPLY=
  local hdr
  hdr=$($UPD_CURL -q --proto '=https' --tlsv1.2 -fsSI --max-time 10 "$UPD_REPO/releases/latest" 2>/dev/null) || return 1
  [[ $hdr == (#b)*[Ll]ocation:[[:blank:]]#[^[:space:]]#/releases/tag/v([0-9][0-9A-Za-z.-]#)* ]] || return 1
  valid_version $match[1] || return 1
  REPLY=$match[1]
}

sha256_of() {
  if [[ -x /usr/bin/shasum ]]; then /usr/bin/shasum -a 256 -- $1
  else sha256sum -- $1; fi | read -r REPLY _
}

# download_release VERSION → REPLY=path of a verified .alfredworkflow
download_release() {
  local v=$1 name="$UPD_PKG-$1.alfredworkflow"
  local url="$UPD_REPO/releases/download/v$v/$name" dst="$UPD_CACHE/$name"
  REPLY=
  rm -f -- $dst $dst.sha256
  $UPD_CURL -q --proto '=https' --tlsv1.2 -fsSL --max-time 120 -o $dst "$url" 2>/dev/null || { UPD_ERR="download failed"; return 1 }
  $UPD_CURL -q --proto '=https' --tlsv1.2 -fsSL --max-time 30 -o $dst.sha256 "$url.sha256" 2>/dev/null || { UPD_ERR="checksum missing"; return 1 }
  local want got
  read -r want _ < $dst.sha256
  sha256_of $dst; got=$REPLY; REPLY=
  [[ -n $want && ${(L)want} == ${(L)got} ]] || { UPD_ERR="checksum mismatch"; rm -f -- $dst; return 1 }
  local plist
  plist=$(unzip -p -- $dst info.plist 2>/dev/null) || { UPD_ERR="not a workflow package"; return 1 }
  [[ $plist == *"<string>$UPD_LABEL</string>"* ]] || { UPD_ERR="wrong bundle id"; return 1 }
  [[ $plist == *$'\n\t<key>version</key>\n\t<string>'"$v</string>"* ]] || { UPD_ERR="version mismatch"; return 1 }
  REPLY=$dst
}

# ---------------------------------------------------------------------------
# Script Filter side
# ---------------------------------------------------------------------------

# update_notice ACTION_SCRIPT: add an "Update available" item (its variables
# route ↩ to the action script) and start the daily background check.
update_notice() {
  local action=$1
  if update_available; then
    item "Update available: $UPD_NAME $REPLY" "You have $(current_version) · ↩ Download and install" \
         "update_install $REPLY" true update '{"action":"update"}'
  fi
  if update_due; then
    # Mark first so repeated keystrokes don't start more checks.
    local seen
    update_available && seen=$REPLY || seen=$(current_version)
    update_mark_checked $seen
    /usr/bin/nohup $action update_check </dev/null >/dev/null 2>&1 &!
  fi
}

# ---------------------------------------------------------------------------
# Action side: print one line for Alfred's notification.
# ---------------------------------------------------------------------------
update_cmd_check() {  # [now] — "now" = asked by the user, always report
  local manual=${1:-}
  if ! fetch_latest; then
    [[ -n $manual ]] && print "Could not reach GitHub to check for updates"
    return 1
  fi
  local latest=$REPLY cur=$(current_version)
  update_mark_checked $latest
  if version_gt $latest $cur; then
    if [[ $CFG_UPDATE == auto && -z $manual ]]; then
      update_cmd_install $latest
      return
    fi
    print "$UPD_NAME $latest is available (you have $cur)"
  else
    [[ -n $manual ]] && print "$UPD_NAME $cur is up to date"
  fi
  return 0
}

update_cmd_install() {  # [version]
  local v=${1:-} cur=$(current_version)
  if [[ -z $v ]]; then
    if update_available; then v=$REPLY; elif fetch_latest; then v=$REPLY; fi
  fi
  [[ -n $v ]] || { print "Could not find the latest release"; return 1 }
  valid_version $v || { print "Invalid version: $v"; return 64 }
  version_gt $v $cur || { print "$UPD_NAME $cur is up to date"; return 0 }
  if ! download_release $v; then
    print "Update not installed: $UPD_ERR"
    return 1
  fi
  $UPD_OPEN $REPLY || { print "Could not open the downloaded update"; return 1 }
  print "Opening $UPD_NAME $v. Confirm the update in Alfred"
}
