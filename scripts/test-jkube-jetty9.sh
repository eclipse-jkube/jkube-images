#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-jetty9:$TAG_OR_LATEST"

assertContains "$(dockerRun 'id')" "uid=1000 gid=0(root) groups=0(root)" || reportError "Invalid run user, should be 1000"

assertContains "$(dockerRun 'java -version')" 'openjdk version "17.0.1"' || reportError "Invalid Java version"

# S2I scripts
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assembleScript="$(dockerRun 'cat /usr/local/s2i/assemble')"
assertContains "$assembleScript" 'copy_dir bin$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir deployments$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir maven$' || reportError "Invalid s2i assemble script"

# Env
env_variables="$(dockerRun 'env')"
assertContains "$env_variables" "JAVA_HOME=/usr/local/openjdk-17$" \
  || reportError "JAVA_HOME invalid"
assertContains "$env_variables" "JAVA_VERSION=17.0.1$" \
  || reportError "JAVA_VERSION invalid"
assertContains "$env_variables" "JETTY_HOME=/usr/local/jetty$" \
  || reportError "JETTY_HOME invalid"
assertContains "$env_variables" "JETTY_BASE=/var/lib/jetty$" \
  || reportError "JETTY_BASE invalid"
assertContains "$env_variables" "TMPDIR=/tmp/jetty$" \
  || reportError "TMPDIR invalid"
assertContains "$env_variables" "DEPLOYMENTS_DIR=/deployments$" \
  || reportError "DEPLOYMENTS_DIR invalid"
