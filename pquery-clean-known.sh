#!/bin/bash
# Created by Roel Van de Paar, Percona LLC

# This script deletes all known found bugs from a pquery work directory. Execute from within the pquery workdir.

# Internal variables
SCRIPT_PWD=$(cd `dirname $0` && pwd)

# Check if this an automated (pquery-reach.sh) run
if [ "$1" == "reach" ]; then
  REACH=1  # Minimal output, and no 2x enter required
else
  REACH=0  # Normal output
fi

# Check if this is a pxc run
if [ "$1" == "pxc" ]; then
  PXC=1
else
  PXC=0
fi

# Current location checks
if [ `ls ./*/pquery_thread-0.sql 2>/dev/null | wc -l` -eq 0 ]; then
  echo "Something is wrong: no pquery trials (with logging - i.e. ./*/pquery_thread-0.sql) were found in this directory"
  exit 1
fi

if [ ${PXC} -eq 1 ]; then
  while read line; do
    STRING="`echo "$line" | sed 's|[ \t]*##.*$||'`"
    if [ "`echo "$STRING" | sed 's|^[ \t]*$||' | grep -v '^[ \t]*#'`" != "" ]; then
      if [ `ls reducer* 2>/dev/null | wc -l` -gt 0 ]; then
        grep -li "${STRING}" reducer* | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | xargs -I_ $SCRIPT_PWD/pquery-del-trial.sh _
      fi
    fi
    #sync; sleep 0.02  # Making sure that next line in file does not trigger same deletions
  done < ${SCRIPT_PWD}/known_bugs_pxc.strings
fi

while read line; do
  STRING="`echo "$line" | sed 's|[ \t]*##.*$||'`"
  if [ "`echo "$STRING" | sed 's|^[ \t]*$||' | grep -v '^[ \t]*#'`" != "" ]; then
    if [ `ls reducer* 2>/dev/null | wc -l` -gt 0 ]; then
      if [ ${PXC} -eq 1 ]; then
        grep -li "${STRING}" reducer* | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | xargs -I_ $SCRIPT_PWD/pquery-del-trial.sh _
      else
        grep -li "${STRING}" reducer* | sed 's/[^0-9]//g' | xargs -I_ $SCRIPT_PWD/pquery-del-trial.sh _
      fi
    fi
  fi
  #sync; sleep 0.02  # Making sure that next line in file does not trigger same deletions
done < ${SCRIPT_PWD}/known_bugs.strings


if [ ${REACH} -eq 0 ]; then  # Avoid normal output if this is an automated run (REACH=1)
  if [ -d ./bundles ]; then
    echo "Done! Any trials in ./bundles were not touched."
  else
    echo "Done!"
  fi
fi
