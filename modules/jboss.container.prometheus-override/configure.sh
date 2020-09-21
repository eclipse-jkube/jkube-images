#!/bin/sh
# Configure module
set -e

SCRIPT_DIR=$(dirname $0)
ARTIFACTS_DIR=${SCRIPT_DIR}/artifacts

chown -R jboss:root ${ARTIFACTS_DIR}
chmod 755 ${ARTIFACTS_DIR}/opt/jboss/container/prometheus/prometheus-opts

pushd ${ARTIFACTS_DIR}
cp -pr * /
popd
