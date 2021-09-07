#!/bin/bash

TAG_OR_LATEST="${TAG:-latest}"

function assertContains() {
  echo "$1" | grep "$2" > /dev/null
}

function reportError() {
  >&2 echo "$1"
  exit 1
}
