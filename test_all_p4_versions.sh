#!/bin/bash


export VCPP4LICENSE=$HOME/p4d_license/license

SAVE_PATH=$PATH
for VER in `./p4version -l`; do
  export PATH=$VER:$SAVE_PATH

  echo "using p4:`which p4` and p4d:`which p4d` in unlicensed mode"
  make test

  if [ ! -z "$VCPP4LICENSE" -a -r "$VCPP4LICENSE" ]; then
    echo "using p4:`which p4` and p4d:`which p4d` in licensed mode"
    make test
  fi

done
