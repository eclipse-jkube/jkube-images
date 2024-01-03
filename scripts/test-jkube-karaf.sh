#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-karaf:$TAG_OR_LATEST"

assertContains "$(dockerRun 'id')" "uid=1000 gid=0(root) groups=0(root)" || reportError "Invalid run user, should be 1000"

java_version="$(dockerRun 'java -version')"
assertMatches "$java_version" 'openjdk version "17.0.[0-9]+' || reportError "Invalid Java version:\n\n$java_version"

# S2I scripts
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assembleScript="$(dockerRun 'cat /usr/local/s2i/assemble')"
assertContains "$assembleScript" 'copy_dir bin$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir deployments$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir maven$' || reportError "Invalid s2i assemble script"
assertContains "$(dockerRun 'cat /usr/local/s2i/run')" 'exec "$KARAF_HOME/bin/karaf" run$' \
  || reportError "Invalid s2i run script"

# Env
env_variables="$(dockerRun 'env')"
assertContains "$env_variables" "JAVA_HOME=/usr/lib/jvm/java-17$" \
  || reportError "JAVA_HOME invalid"
assertContains "$env_variables" "JAVA_VERSION=17$" \
  || reportError "JAVA_VERSION invalid"
assertContains "$env_variables" "KARAF_HOME=/deployments/karaf$" \
  || reportError "KARAF_HOME invalid"
assertContains "$env_variables" "DEPLOYMENTS_DIR=/deployments$" \
  || reportError "DEPLOYMENTS_DIR invalid"
assertContains "$env_variables" "JBOSS_CONTAINER_JAVA_RUN_MODULE=/opt/jboss/container/java/run$" \
  || reportError "JBOSS_CONTAINER_JAVA_RUN_MODULE invalid"
assertContains "$env_variables" "JBOSS_CONTAINER_JAVA_S2I_MODULE=/opt/jboss/container/java/s2i$" \
  || reportError "JBOSS_CONTAINER_JAVA_S2I_MODULE invalid"
assertContains "$env_variables" "JBOSS_CONTAINER_MAVEN_DEFAULT_MODULE=/opt/jboss/container/maven/default/$" \
  || reportError "JBOSS_CONTAINER_MAVEN_DEFAULT_MODULE invalid"
assertContains "$env_variables" "JBOSS_CONTAINER_S2I_CORE_MODULE=/opt/jboss/container/s2i/core/$" \
  || reportError "JBOSS_CONTAINER_S2I_CORE_MODULE invalid"
