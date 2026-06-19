#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-jetty12:$TAG_OR_LATEST"

assertContains "$(dockerRun 'id')" "uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu)" || reportError "Invalid run user, should be 1000"

java_version="$(dockerRun 'java -version')"
assertMatches "$java_version" 'openjdk version "21.[0-9]+.[0-9]+"' || reportError "Invalid Java version:\n\n$java_version"

# S2I scripts
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assertMatches "$s2i" '^-rwx.* run$' || reportError "/usr/local/s2i/run is not executable"
assembleScript="$(dockerRun 'cat /usr/local/s2i/assemble')"
assertContains "$assembleScript" 'copy_dir bin$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir deployments$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir maven$' || reportError "Invalid s2i assemble script"
runScript="$(dockerRun 'cat /usr/local/s2i/run')"
assertContains "$runScript" 'DEPLOY_DIR' || reportError "Invalid s2i run script: missing DEPLOY_DIR"
assertContains "$runScript" 'JETTY_BASE' || reportError "Invalid s2i run script: missing JETTY_BASE"
assertContains "$runScript" 'start.jar' || reportError "Invalid s2i run script: missing start.jar"

# Jetty ee10-deploy module
jetty_modules="$(dockerRun 'ls /var/lib/jetty/start.d/')"
assertContains "$jetty_modules" "ee10-deploy" || reportError "ee10-deploy module not enabled"

# Webapps directory
webapps_dir="$(dockerRun 'ls /var/lib/jetty/')"
assertContains "$webapps_dir" "webapps" || reportError "webapps directory not found in JETTY_BASE"
assertContains "$(dockerRun 'stat -c %u /var/lib/jetty/webapps')" '^1000$' \
  || reportError "JETTY_BASE/webapps should be owned by uid 1000"

# Env
env_variables="$(dockerRun 'env')"
assertContains "$env_variables" "JAVA_HOME=/opt/java/openjdk$" \
  || reportError "JAVA_HOME invalid"
assertMatches "$env_variables" "JAVA_VERSION=jdk-21.[0-9]+.[0-9]+\\+[0-9]+" \
  || reportError "JAVA_VERSION invalid"
assertContains "$env_variables" "JETTY_HOME=/usr/local/jetty$" \
  || reportError "JETTY_HOME invalid"
assertContains "$env_variables" "JETTY_BASE=/var/lib/jetty$" \
  || reportError "JETTY_BASE invalid"
assertContains "$env_variables" "TMPDIR=/tmp/jetty$" \
  || reportError "TMPDIR invalid"
assertContains "$env_variables" "DEPLOYMENTS_DIR=/deployments$" \
  || reportError "DEPLOYMENTS_DIR invalid"
assertMatches "$env_variables" "JETTY_VERSION=12.0.[0-9]+" \
  || reportError "JETTY_VERSION invalid"
