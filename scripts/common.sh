#!/bin/bash

TAG_OR_LATEST="${TAG:-latest}"

# Run command in docker container for configured image, the first argument is the command to run in the container
function dockerRun() {
  read -ra COMMAND <<<"$1"
  output=$(docker run  --rm --pull never "$IMAGE" "${COMMAND[@]}" 2>&1)
  echo "$output";
}

# Run command in docker container for configured allowing to pass arguments including quotes and spaces
function dockerRunE() {
  output=$(docker run  --rm --pull never "$IMAGE" "${@}" 2>&1)
  echo "$output";
}

function assertContains() {
  echo "$1" | grep "$2" > /dev/null
}

function assertMatches() {
  echo "$1" | grep -E "$2" > /dev/null
}

function reportError() {
  >&2 printf "$1"
  exit 1
}
