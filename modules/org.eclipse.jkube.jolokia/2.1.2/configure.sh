#!/bin/sh
# Configure module
set -e

SCRIPT_DIR=$(dirname $0)
ARTIFACTS_DIR=${SCRIPT_DIR}/artifacts

# Copy main artifact
mkdir -p /usr/share/java/jolokia-jvm-agent/
cp /tmp/artifacts/jolokia-jvm.jar /usr/share/java/jolokia-jvm-agent/

# Copy module artifacts
chown -R jboss:root $SCRIPT_DIR
chmod -R ug+rwX $SCRIPT_DIR
chmod ug+x ${ARTIFACTS_DIR}/opt/jboss/container/jolokia/*

pushd ${ARTIFACTS_DIR}
cp -pr * /
popd

mkdir -p /opt/jboss/container/jolokia/etc
chmod 775 /opt/jboss/container/jolokia/etc
chown -R jboss:root /opt/jboss/container/jolokia/etc
