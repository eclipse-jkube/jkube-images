#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-java:$TAG_OR_LATEST"
env_variables="$(dockerRun 'env')"

# User
assertContains "$(dockerRun 'id')" "uid=1000 gid=0(root) groups=0(root)" || reportError "Invalid run user, should be 1000"
assertMatches "$(dockerRun 'pwd')" '/home/jboss' || reportError "Invalid home directory"

# Java (xxx.openjdk.jdk)
java_version="$(dockerRun 'java -version')"
assertMatches "$java_version" 'openjdk version "21.0.[0-9]+' || reportError "Invalid Java version:\n\n$java_version"
assertContains "$env_variables" "JAVA_HOME=/usr/lib/jvm/java-21$" \
  || reportError "JAVA_HOME invalid"
assertContains "$env_variables" "JAVA_VERSION=21$" \
  || reportError "JAVA_VERSION invalid"
assertContains "$env_variables" "JBOSS_CONTAINER_OPENJDK_JDK_MODULE=/opt/jboss/container/openjdk/jdk$" \
  || reportError "JBOSS_CONTAINER_OPENJDK_JDK_MODULE invalid"
jvm_options="$(dockerRunE /bin/bash -c '. /opt/jboss/container/openjdk/jdk/jvm-options && jvm_specific_diagnostics')" || reportError "Failed to get jvm_options"
assertMatches "$jvm_options" '\-Xlog:gc::utctime -XX:NativeMemoryTracking=summary$' || reportError "Invalid jvm_options:\n\n$jvm_options"

maven_version="$(dockerRun 'mvn -version')"
assertMatches "$maven_version" 'Apache Maven 3.8.[0-9]+' || reportError "Invalid Maven version:\n\n$maven_version"

# run-java dependent scripts (xxx.java.jvm.bash)
jvm_tools="$(dockerRun 'ls -la /opt/jboss/container/java/jvm/')"
assertContains "$jvm_tools" "container-limits$" || reportError "container-limits not found"
assertContains "$jvm_tools" "debug-options$" || reportError "debug-options not found"
assertContains "$jvm_tools" "java-default-options$" || reportError "java-default-options not found"
# java-default-options default
java_default_options="$(dockerRunE '/opt/jboss/container/java/jvm/java-default-options')" || reportError "Failed to get java_default_options"
assertMatches "$java_default_options" '^-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -XX:\+ExitOnOutOfMemoryError$' \
  || reportError "Invalid java_default_options:\n\n$java_default_options"
# java-default-options override with JAVA_DIAGNOSTICS
java_default_options="$(dockerRunE /bin/bash -c 'JAVA_DIAGNOSTICS=true /opt/jboss/container/java/jvm/java-default-options')"|| reportError "Failed to get java_default_options"
assertMatches "$java_default_options" '^-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -Xlog:gc::utctime -XX:NativeMemoryTracking=summary -XX:\+ExitOnOutOfMemoryError$' \
  || reportError "Invalid java_default_options (JAVA_DIAGNOSTICS):\n\n$java_default_options"
# java-default-options override with blank GC_CONTAINER_OPTIONS env (Unsupported -XX:+UseParallelOldGC is listed)
java_default_options="$(dockerRunE /bin/bash -c 'GC_CONTAINER_OPTIONS="" /opt/jboss/container/java/jvm/java-default-options')"|| reportError "Failed to get java_default_options"
assertMatches "$java_default_options" "^-XX:\+UseParallelOldGC -XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -XX:\+ExitOnOutOfMemoryError$" \
  || reportError "Invalid java_default_options (GC_CONTAINER_OPTIONS):\n\n$java_default_options"

# debug-options-override
debug_options="$(dockerRun 'cat /opt/jboss/container/java/jvm/debug-options')"
assertContains "$debug_options" "[-]agentlib:jdwp=transport=dt_socket,server=y,suspend=\${suspend_mode},address=\${debug_port}" \
  || reportError "Overridden debug-options is wrong"

# Default run-java module (xxx.java.run.bash)
run_java="$(dockerRun 'ls -la /opt/jboss/container/java/run/')"
assertContains "$run_java" "run-env.sh" || reportError "run-env.sh not found"
assertContains "$run_java" "run-java.sh" || reportError "run-java.sh not found"
# shellcheck disable=SC2016
run_java_exec="$(dockerRunE /bin/bash -c 'JAVA_APP_JAR=$JAVA_HOME/lib/jrt-fs.jar /opt/jboss/container/java/run/run-java.sh')" || reportError "Failed to get run_java_exec"
assertMatches "$run_java_exec" ".+java -XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -XX:\+ExitOnOutOfMemoryError -cp \".\" -jar.+" \
  || reportError "Invalid run_java_exec:\n\n$run_java_exec"

# Jolokia module
jolokia_jar="$(dockerRun 'ls -la /usr/share/java/jolokia-jvm-agent/')"
assertContains "$jolokia_jar" "jolokia-jvm.jar" || reportError "jolokia-jvm.jar not found"
jolokia="$(dockerRun 'ls -la /opt/jboss/container/jolokia/')"
assertContains "$jolokia" "jolokia-opts" || reportError "jolokia-opts not found"
assertContains "$jolokia" "etc" || reportError "etc not found"

# Prometheus module
prometheus_jar="$(dockerRun 'ls -la /usr/share/java/prometheus-jmx-exporter/')"
assertContains "$prometheus_jar" "jmx_prometheus_javaagent.jar" || reportError "jmx_prometheus_javaagent.jar not found"
prometheus="$(dockerRun 'ls -la /opt/jboss/container/prometheus/')"
assertContains "$prometheus" "prometheus-opts" || reportError "prometheus-opts not found"
assertContains "$prometheus" "etc" || reportError "etc not found"

# S2I (xxx.java.s2i.bash)
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assertContains "$(dockerRun 'cat /usr/local/s2i/assemble')" 'maven_s2i_build$' || reportError "Invalid s2i assemble script"
# shellcheck disable=SC2016
s2i_run="$(dockerRunE /bin/bash -c 'JAVA_APP_JAR=$JAVA_HOME/lib/jrt-fs.jar /usr/local/s2i/run')" || reportError "Failed to get s2i_run"
assertJolokia="-javaagent:/usr/share/java/jolokia-jvm-agent/jolokia-jvm.jar=config=/opt/jboss/container/jolokia/etc/jolokia.properties"
assertPrometheus="-javaagent:/usr/share/java/prometheus-jmx-exporter/jmx_prometheus_javaagent.jar=9779:/opt/jboss/container/prometheus/etc/jmx-exporter-config.yaml"
assertJavaExec="-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -XX:\+ExitOnOutOfMemoryError -cp \".\" -jar"
assertMatches "$s2i_run" ".+java $assertJolokia $assertPrometheus $assertJavaExec.+" \
  || reportError "Invalid run_java_exec:\n\n$s2i_run"

# Generic environment variables
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
assertContains "$env_variables" "JOLOKIA_VERSION=2.0.0$" \
  || reportError "JOLOKIA_VERSION invalid"
assertContains "$env_variables" "AB_JOLOKIA_PASSWORD_RANDOM=true$" \
  || reportError "AB_JOLOKIA_PASSWORD_RANDOM invalid"
assertContains "$env_variables" "AB_JOLOKIA_HTTPS=true$" \
  || reportError "AB_JOLOKIA_HTTPS invalid"
assertContains "$env_variables" "AB_PROMETHEUS_JMX_EXPORTER_CONFIG=/opt/jboss/container/prometheus/etc/jmx-exporter-config.yaml$" \
  || reportError "AB_PROMETHEUS_JMX_EXPORTER_CONFIG invalid"
assertContains "$env_variables" "GC_CONTAINER_OPTIONS= $" \
  || reportError "GC_CONTAINER_OPTIONS invalid"

# Additional tools
netstat_version="$(dockerRun 'netstat --version')"
assertMatches "$netstat_version" 'net-tools 2.[0-9]+' || reportError "Invalid netstat (net-tools) version:\n\n$netstat_version"

ps_version="$(dockerRun 'ps --version')"
assertMatches "$ps_version" 'ps from procps-ng 3.3.[0-9]+' || reportError "Invalid ps (procps-ng) version:\n\n$ps_version"
