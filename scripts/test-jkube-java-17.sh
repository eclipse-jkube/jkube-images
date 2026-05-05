#!/bin/bash

set -Eeuo pipefail
trap 'exit' ERR
BASEDIR=$(dirname "$BASH_SOURCE")
source "$BASEDIR/common.sh"

IMAGE="quay.io/jkube/jkube-java-17:$TAG_OR_LATEST"
env_variables="$(dockerRun 'env')"

# User
assertMatches "$(dockerRun 'id')" 'uid=1000([^ ]*)? gid=0\(root\) groups=0\(root\)' || reportError "Invalid run user, should be 1000"
assertMatches "$(dockerRun 'pwd')" '/home/jboss' || reportError "Invalid home directory"

# Java (xxx.openjdk.jdk)
java_version="$(dockerRun 'java -version')"
assertMatches "$java_version" 'openjdk version "17.0.[0-9]+' || reportError "Invalid Java version:\n\n$java_version"
assertContains "$env_variables" "JAVA_HOME=/usr/lib/jvm/java-17$" \
  || reportError "JAVA_HOME invalid"
assertContains "$env_variables" "JAVA_VERSION=17$" \
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
run_java_exec="$(dockerRunE /bin/bash -c '(JAVA_APP_JAR=$JAVA_HOME/lib/jrt-fs.jar /opt/jboss/container/java/run/run-java.sh); exit 0')" || reportError "Failed to get run_java_exec"
assertMatches "$run_java_exec" ".+java -XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=20 -XX:GCTimeRatio=4 -XX:AdaptiveSizePolicyWeight=90 -XX:\+ExitOnOutOfMemoryError -cp \".\" -jar.+" \
  || reportError "Invalid run_java_exec:\n\n$run_java_exec"

# Jolokia module
jolokia_jar="$(dockerRun 'ls -la /usr/share/java/jolokia-jvm-agent/')"
assertContains "$jolokia_jar" "jolokia-jvm.jar" || reportError "jolokia-jvm.jar not found"
jolokia_version_props="$(dockerRunE /bin/bash -c 'cd /tmp && jar xf /usr/share/java/jolokia-jvm-agent/jolokia-jvm.jar version.properties && cat version.properties')"
assertMatches "$jolokia_version_props" "jolokia\.version = 2\.6\.0" \
  || reportError "Jolokia jar version mismatch:\n\n$jolokia_version_props"
jolokia="$(dockerRun 'ls -la /opt/jboss/container/jolokia/')"
assertContains "$jolokia" "jolokia-opts" || reportError "jolokia-opts not found"
assertContains "$jolokia" "etc" || reportError "etc not found"
# Verify jolokia-opts is executable
assertMatches "$jolokia" '^-rwx.*jolokia-opts$' || reportError "jolokia-opts is not executable"
# Verify jolokia-opts produces the expected javaagent string
jolokia_opts_output="$(dockerRunE /bin/bash -c '. /opt/jboss/container/jolokia/jolokia-opts')" || reportError "Failed to run jolokia-opts"
assertContains "$jolokia_opts_output" "-javaagent:/usr/share/java/jolokia-jvm-agent/jolokia-jvm.jar=config=/opt/jboss/container/jolokia/etc/jolokia.properties" \
  || reportError "jolokia-opts output invalid:\n\n$jolokia_opts_output"
# Verify jolokia-opts respects AB_JOLOKIA_OFF
jolokia_off_output="$(dockerRunE /bin/bash -c 'AB_JOLOKIA_OFF=true . /opt/jboss/container/jolokia/jolokia-opts')" || true
! assertContains "$jolokia_off_output" "-javaagent:" \
  || reportError "jolokia-opts should not emit -javaagent when AB_JOLOKIA_OFF is set:\n\n$jolokia_off_output"
# Verify OpenShift cert-auth branch activates when SA ca.crt is present
ca_dir="$(mktemp -d)"
trap 'rm -rf "$ca_dir"' EXIT
: > "$ca_dir/ca.crt"
jolokia_openshift_props="$(docker run --rm --pull never \
    -v "$ca_dir/ca.crt:/var/run/secrets/kubernetes.io/serviceaccount/ca.crt:ro" \
    "$IMAGE" /bin/bash -c '. /opt/jboss/container/jolokia/jolokia-opts \
      && cat /opt/jboss/container/jolokia/etc/jolokia.properties' 2>&1)"
assertContains "$jolokia_openshift_props" "useSslClientAuthentication=true" \
  || reportError "OpenShift client cert auth not enabled when ca.crt is present"
assertContains "$jolokia_openshift_props" "extendedClientCheck=true" \
  || reportError "extendedClientCheck not enabled in OpenShift cert-auth properties"
assertContains "$jolokia_openshift_props" "protocol=https" \
  || reportError "Jolokia protocol should be https when OpenShift auth is active"
assertContains "$jolokia_openshift_props" "caCert=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt" \
  || reportError "caCert path missing in jolokia.properties"
assertContains "$jolokia_openshift_props" "clientPrincipal=cn=system:master-proxy" \
  || reportError "Default OpenShift clientPrincipal missing"
# Verify JBOSS_CONTAINER_JOLOKIA_MODULE env var
assertContains "$env_variables" "JBOSS_CONTAINER_JOLOKIA_MODULE=/opt/jboss/container/jolokia$" \
  || reportError "JBOSS_CONTAINER_JOLOKIA_MODULE invalid"

# Prometheus module
prometheus_jar="$(dockerRun 'ls -la /usr/share/java/prometheus-jmx-exporter/')"
assertContains "$prometheus_jar" "jmx_prometheus_javaagent.jar" || reportError "jmx_prometheus_javaagent.jar not found"
prometheus="$(dockerRun 'ls -la /opt/jboss/container/prometheus/')"
assertContains "$prometheus" "prometheus-opts" || reportError "prometheus-opts not found"
assertContains "$prometheus" "etc" || reportError "etc not found"
assertMatches "$prometheus" 'rwx.*prometheus-opts' || reportError "prometheus-opts is not executable"
prometheus_config="$(dockerRun 'ls -la /opt/jboss/container/prometheus/etc/')"
assertContains "$prometheus_config" "jmx-exporter-config.yaml" || reportError "jmx-exporter-config.yaml not found"
prometheus_opts_output="$(dockerRunE /bin/bash -c 'source /opt/jboss/container/prometheus/prometheus-opts && get_prometheus_opts')" || reportError "Failed to run prometheus-opts"
assertContains "$prometheus_opts_output" "-javaagent:/usr/share/java/prometheus-jmx-exporter/jmx_prometheus_javaagent.jar=9779:/opt/jboss/container/prometheus/etc/jmx-exporter-config.yaml" \
  || reportError "prometheus-opts output invalid:\n\n$prometheus_opts_output"
prometheus_off_output="$(dockerRunE /bin/bash -c 'AB_PROMETHEUS_OFF=true source /opt/jboss/container/prometheus/prometheus-opts && get_prometheus_opts')" || true
assertMatches "$prometheus_off_output" '^$' || reportError "prometheus-opts should produce no javaagent when AB_PROMETHEUS_OFF is set:\n\n$prometheus_off_output"
assertContains "$env_variables" "JBOSS_CONTAINER_PROMETHEUS_MODULE=/opt/jboss/container/prometheus$" \
  || reportError "JBOSS_CONTAINER_PROMETHEUS_MODULE invalid"

# S2I (xxx.java.s2i.bash)
s2i="$(dockerRun 'ls -la /usr/local/s2i/')"
assertContains "$s2i" "assemble" || reportError "assemble not found"
assertContains "$s2i" "run" || reportError "run not found"
assertContains "$(dockerRun 'cat /usr/local/s2i/assemble')" 'maven_s2i_build$' || reportError "Invalid s2i assemble script"
# shellcheck disable=SC2016
s2i_run="$(dockerRunE /bin/bash -c '(JAVA_APP_JAR=$JAVA_HOME/lib/jrt-fs.jar /usr/local/s2i/run); exit 0')" || reportError "Failed to get s2i_run"
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
assertContains "$env_variables" "JOLOKIA_VERSION=2.6.0$" \
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
