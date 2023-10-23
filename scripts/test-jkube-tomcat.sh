#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-tomcat:$TAG_OR_LATEST"

assertContains "$(dockerRun 'id')" "uid=1000 gid=0(root) groups=0(root)" || reportError "Invalid run user, should be 1000"

java_version="$(dockerRun 'java -version')"
assertMatches "$java_version" 'openjdk version "21"' || reportError "Invalid Java version:\n\n$java_version"

# S2I scripts
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assembleScript="$(dockerRun 'cat /usr/local/s2i/assemble')"
assertContains "$assembleScript" 'copy_dir bin$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir deployments$' || reportError "Invalid s2i assemble script"
assertContains "$assembleScript" 'copy_dir maven$' || reportError "Invalid s2i assemble script"
runScript="$(dockerRun 'cat /usr/local/s2i/run')"
assertContains "$runScript" 'webappsDir=${TOMCAT_WEBAPPS_DIR:-"webapps"}' || reportError "Invalid s2i run script"
assertContains "$runScript" 'target="${CATALINA_HOME}/${webappsDir}"' || reportError "Invalid s2i run script"

# Legacy webapps directory
tomcatDir="$(dockerRun 'ls /usr/local/tomcat/')"
assertContains "$tomcatDir" "^webapps-javaee$" || reportError "webapps-javaee not found"

# Env
env_variables="$(dockerRun 'env')"
assertContains "$env_variables" "JAVA_HOME=/opt/java/openjdk$" \
  || reportError "JAVA_HOME invalid"
assertMatches "$env_variables" "JAVA_VERSION=jdk-21\\+35" \
  || reportError "JAVA_VERSION invalid"
assertContains "$env_variables" "CATALINA_HOME=/usr/local/tomcat$" \
  || reportError "CATALINA_HOME invalid"
assertMatches "$env_variables" "TOMCAT_VERSION=10.1.[0-9A-Z-]+$" \
  || reportError "TOMCAT_VERSION invalid"
assertContains "$env_variables" "DEPLOYMENTS_DIR=/deployments$" \
  || reportError "DEPLOYMENTS_DIR invalid"
