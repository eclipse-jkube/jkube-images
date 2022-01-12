#!/bin/bash

TAG_OR_LATEST="${TAG:-latest}"

function dockerRun() {
  read -ra COMMAND <<<"$1"
  output=$(docker run  --rm --pull never "$IMAGE" "${COMMAND[@]}" 2>&1)
  echo "$output";
}

function assertContains() {
  echo "$1" | grep "$2" > /dev/null
}

function reportError() {
  >&2 echo "$1"
  exit 1
}
