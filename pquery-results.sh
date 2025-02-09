#!/bin/bash
# Created by Roel Van de Paar, Percona LLC
# Usage example"
#  For normal output            : $./pquery-results.sh
#  For Valgrind + normal output : $./pquery-results.sh valgrind

# Internal variables
SCRIPT_PWD=$(cd `dirname $0` && pwd)

# Check if this is a pxc run
if [ "`echo $1 | sed 's|PXC|pxc|i'`" == "pxc" ]; then
  PXC=1
else
  PXC=0
fi

# Current location checks
if [ `ls ./*/pquery_thread-0.sql 2>/dev/null | wc -l` -eq 0 ]; then
  echo "Something is wrong: no pquery trials (with logging - i.e. ./*/pquery_thread-0.sql) were found in this directory (or they were all cleaned up already)"
  echo "Please make sure to execute this script from within the pquery working directory!"
  exit 1
elif [ `ls ./reducer* 2>/dev/null | wc -l` -eq 0 ]; then
  echo "Something is wrong: no reducer scripts were found in this directory. Did you forgot to execute ${SCRIPT_PWD}/pquery-prep-red.sh ?"
  exit 1
fi

TRIALS_EXECUTED=$(cat pquery-run.log | grep -o "==.*TRIAL.*==" | tail -n1 | sed 's|[^0-9]*||;s|[ \t=]||g')
echo "================ Sorted unique issue strings (${TRIALS_EXECUTED} trials executed, `ls reducer*.sh | wc -l` remaining reducer scripts)"
ORIG_IFS=$IFS; IFS=$'\n'  # Use newline seperator instead of space seperator in the for loop
if [ $PXC == 0 ]; then
  for STRING in `grep "   TEXT=" reducer* | sed 's|.*TEXT="||;s|"$||' | sort -u`; do
    COUNT=`grep "   TEXT=" reducer* | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep "${STRING}" | wc -l`
    MATCHING_TRIALS=`grep -H "   TEXT=" reducer* | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep "${STRING}" | sed 's|.sh.*||;s|reducer||' | tr '\n' ',' | sed 's|,$||'`
    STRING_OUT=`echo $STRING | awk -F "\n" '{printf "%-55s",$1}'`
    COUNT_OUT=`echo $COUNT | awk '{printf "(Seen %3s times: reducers ",$1}'`
    echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS})"
  done
else
  for STRING in `grep "   TEXT=" reducer* | sed 's|.*TEXT="||;s|"$||' | sort -u`; do
    MATCHING_TRIALS=()
    for TRIAL in `grep -H ${STRING} reducer* | awk '{ print $1}' | cut -d'-' -f1 | tr -d '[:alpha:]' | uniq` ; do
      MATCHING_TRIAL=`grep -H "   TEXT=" reducer${TRIAL}-* | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep "${STRING}" | sed "s|.sh.*||;s|reducer${TRIAL}-||" | tr '\n' ',' | sed 's|,$||' | xargs -I {} echo "[${TRIAL}-{}] "`
      MATCHING_TRIALS+=("$MATCHING_TRIAL")
    done
    COUNT=`grep "   TEXT=" reducer* | sed 's|reducer\([0-9]\).sh:|reducer\1.sh:  |;s|reducer\([0-9][0-9]\).sh:|reducer\1.sh: |;s|  TEXT|TEXT|' | grep "${STRING}" | wc -l`
    STRING_OUT=`echo $STRING | awk -F "\n" '{printf "%-55s",$1}'`
    COUNT_OUT=`echo $COUNT | awk '{printf "(Seen %3s times: reducers ",$1}'`
    echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})"
  done
fi
IFS=$ORIG_IFS
# MODE 4 TRIALS
if [ $PXC == 0 ]; then
  COUNT=`grep -l "^MODE=4$" reducer* | wc -l`
  if [ $COUNT -gt 0 ]; then
    MATCHING_TRIALS=`grep -l "^MODE=4$" reducer* | tr -d '\n' | sed 's|reducer|,|g;s|[.sh]||g;s|^,||'`
    STRING_OUT=`echo "* TRIALS TO CHECK MANUALLY (NO TEXT SET: MODE=4) *" | awk -F "\n" '{printf "%-55s",$1}'`
    COUNT_OUT=`echo $COUNT | awk '{printf "(Seen %3s times: reducers ",$1}'`
    echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS})"
  fi
else
  COUNT=`grep -l "^MODE=4$" reducer* | wc -l`
  if [ $COUNT -gt 0 ]; then
    MATCHING_TRIALS=()
    for TRIAL in `grep -H "^MODE=4$" reducer* | awk '{ print $1}' | cut -d'-' -f1 | tr -d '[:alpha:]' | uniq` ; do
      MATCHING_TRIAL=`grep -H "^MODE=4$" reducer${TRIAL}-* | sed "s|.sh.*||;s|reducer${TRIAL}-||" | tr '\n' , | sed 's|,$||' | xargs -I '{}' echo "[${TRIAL}-{}] "`
      MATCHING_TRIALS+=("$MATCHING_TRIAL")
    done
    STRING_OUT=`echo "* TRIALS TO CHECK MANUALLY (NO TEXT SET: MODE=4) *" | awk -F "\n" '{printf "%-55s",$1}'`
    COUNT_OUT=`echo $COUNT | awk '{printf "(Seen %3s times: reducers ",$1}'`
    echo -e "${STRING_OUT}${COUNT_OUT}${MATCHING_TRIALS[@]})"
  fi
fi
echo "================"
if [ `ls -l reducer* | awk '{print $5"|"$9}' | grep "^0|" | sed 's/^0|//' | wc -l` -gt 0 ]; then
  echo "Detected some empty (0 byte) reducer scripts: `ls -l reducer* | awk '{print $5"|"$9}' | grep "^0|" | sed 's/^0|//' | tr '\n' ' '`- you may want to check what's causing this (possibly a bug in pquery-prep-red.sh, or did you simply run out of space while running pquery-prep-red.sh?) and do the analysis for these trial numbers manually, or free some space, delete the reducer*.sh scripts and re-run pquery-prep-red.sh"
fi

extract_valgrind_error(){
  for i in $( ls  */log/master.err ); do
    TRIAL=`echo $i | cut -d'/' -f1`
    echo "============ Trial $TRIAL ===================="
    egrep --no-group-separator  -A4 "Thread[ \t][0-9]+:" $i | cut -d' ' -f2- |  sed 's/0x.*:[ \t]\+//' |  sed 's/(.*)//' | rev | cut -d '(' -f2- | sed 's/^[ \t]\+//' | rev  | sed 's/^[ \t]\+//'  |  tr '\n' '|' |xargs |  sed 's/Thread[ \t][0-9]\+:/\nIssue #/ig'
  done
}

if [ ! -z $1 ]; then
  extract_valgrind_error
fi
