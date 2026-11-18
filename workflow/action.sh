#!/bin/zsh -f
# action.sh — Run Script action for update items (clipboard items never get here).
#
#   action.sh "update_check [now]"     check GitHub for a newer release
#   action.sh "update_install X.Y.Z"   download, verify, open in Alfred
source "${0:A:h}/lib/common.zsh"
source $NI_WF_DIR/lib/update.zsh
(( $# == 1 )) && set -- ${(z)1}
case ${1:-} in
  update_check)   update_cmd_check ${2:-} ;;
  update_install) update_cmd_install ${2:-} ;;
  *)              print "Unknown action"; exit 64 ;;
esac
