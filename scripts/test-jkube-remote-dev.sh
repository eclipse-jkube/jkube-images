#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-remote-dev:$TAG_OR_LATEST"

sshd_config="$(dockerRun 'cat /etc/ssh/sshd_config')"


assertMatches "$sshd_config" "^PasswordAuthentication no$" \
  || reportError "SSHD config has invalid PasswordAuthentication"
assertMatches "$sshd_config" "^AllowTcpForwarding yes$" \
  || reportError "SSHD config has invalid AllowTcpForwarding"
assertMatches "$sshd_config" "^GatewayPorts clientspecified$" \
  || reportError "SSHD config has invalid GatewayPorts"
assertMatches "$sshd_config" "^AuthorizedKeysFile /opt/ssh-config/authorized_keys$" \
  || reportError "SSHD config has invalid AuthorizedKeysFile"
assertMatches "$sshd_config" "^StrictModes no$" \
  || reportError "SSHD config has invalid StrictModes"
