#!/bin/bash -ue

# Author: Raghavendra Prabhu <raghavendra.prabhu@percona.com>

set +e
echo "Killing existing mysqld"
pgrep -f mysqld

pkill -f mysqld
sleep 10
pgrep mysqld || pkill -9 -f mysqld
set -e 

sleep 5


LPATH=${SPATH:-/usr/share/doc/sysbench/tests/db}

SBENCH="sysbench"
XB_VER=2.2.1
WORKDIR=$1
ROOT_FS=$WORKDIR
sst_method=${SST_METHOD:-xtrabackup-v2}

GVER="galera${GALERA_VER:-2}"

cd $WORKDIR

if [[ $sst_method == xtrabackup-v2 ]];then
    TAR=`ls -1ct percona-xtrabackup*.tar.gz | head -n1`
    #BBASE="$(basename $TAR .tar.gz)"
    tar -xf $TAR
    BBASE="percona-xtrabackup-${XB_VER}-Linux-x86_64"
    export PATH="$ROOT_FS/$BBASE/bin:$PATH"
fi

count=$(ls -1ct Percona-XtraDB-Cluster*.tar.gz | wc -l)

if [[ $count -gt 1 ]];then 
    for dirs in `ls -1ct Percona-XtraDB-Cluster*.tar.gz | tail -n +2`;do 
        rm -rf $dirs
    done 
fi

find . -maxdepth 1 -type d -name 'Percona-XtraDB-Cluster*' -exec rm -rf {} \+

echo "Removing older core files, if any"
rm -f ${ROOT_FS}/**/*core* 

echo "Removing older directories"
find . -maxdepth 1 -type d -mtime +10 -exec rm -rf {} \+

echo "Removing their symlinks"
find . -maxdepth 1 -type l -mtime +10 -delete

TAR=`ls -1ct Percona-XtraDB-Cluster*.tar.gz | head -n1`
#BASE="$(basename $TAR .tar.gz)"
BASE="$(tar tf $TAR | head -1 | tr -d '/')"

if [[ -n ${EXTERNALS:-} ]];then 
    EXTOPTS="$EXTERNALS"
else
    EXTOPTS=""
fi

if [[ $DEBUG -eq 1 ]];then 
    DBG="--mysqld=--wsrep-debug=1"
else 
    DBG=""
fi

if [[ $MEM -eq 1 ]];then 
    MEMOPT="--mem"
else 
    MEMOPT=""
fi


tar -xf $TAR

# Keep (PS & QA) builds & results for ~40 days (~1/day)
BUILD_WIPE=$[ ${BUILD_NUMBER} - 40 ]
if [ -d ${BUILD_WIPE} ]; then rm -Rf ${BUILD_WIPE}; fi

# For Sysbench
if [[ "x${Host}" == "xubuntu-trusty-64bit" ]];then
    export CFLAGS="-Wl,--no-undefined -lasan"
fi

if [[ ! -e `which sysbench` ]];then 
    echo "Sysbench not found" 
    exit 1
fi
echo "Note: Using sysbench at $(which sysbench)"

# Parameter of parameterized build 
if [[ -n $SDURATION ]];then 
    export SYSBENCH_DURATION=$SDURATION
else 
    export SYSBENCH_DURATION=300
fi

WORKDIR="${ROOT_FS}/$BUILD_NUMBER"

mkdir -p $WORKDIR/logs
# User settings
SENDMAIL="/usr/sbin/sendmail"

cleanup(){
    tar cvzf $ROOT_FS/results-${BUILD_NUMBER}.tar.gz $WORKDIR/logs || true
}


trap cleanup EXIT KILL

prepare()
{
    local sock=$1
    local log=$2

    echo "Sysbench Run: Prepare stage"
    $SBENCH --test=$LPATH/parallel_prepare.lua --report-interval=10  --oltp-auto-inc=$AUTOINC --mysql-engine-trx=yes --mysql-table-engine=innodb \
        --oltp-table-size=$TSIZE --oltp_tables_count=$TCOUNT --mysql-db=test --mysql-user=root  --num-threads=$NUMT \
        --db-driver=mysql --mysql-socket=$sock prepare 2>&1 | tee $log

    $MYSQL_BASEDIR/bin/mysql  -S $sock -u root -e "create database testdb;" || true
}


ver_and_row(){
    local sock=$1
    

    $MYSQL_BASEDIR/bin/mysql -S $sock  -u root -e "show global variables like 'version';"

    $MYSQL_BASEDIR/bin/mysql -S $sock  -u root -e "select count(*) from $STABLE;"
    $MYSQL_BASEDIR/bin/mysql -S $sock  -u root -e "select count(*) from $STABLE;"
}

rw_full()
{

    local sock=$1
    local log=$2
    echo "Sysbench Run: OLTP RW testing"
    $SBENCH --mysql-table-engine=innodb --num-threads=$NUMT --report-interval=10 --oltp-auto-inc=$AUTOINC --max-time=$SYSBENCH_DURATION --max-requests=1870000000 \
        --test=$SDIR/$STEST.lua --init-rng=on --oltp_index_updates=10 --oltp_non_index_updates=10 --oltp_distinct_ranges=15 --oltp_order_ranges=15 --oltp_tables_count=$TCOUNT --mysql-db=test \
        --mysql-user=root --db-driver=mysql --mysql-socket=$sock  run 2>&1 | tee $log
}



WORKDIR="${ROOT_FS}/$BUILD_NUMBER"
mkdir -p $WORKDIR

MYSQL_BASEDIR="${ROOT_FS}/$BASE"
export MYSQL_VARDIR="$WORKDIR/mysqldir"
mkdir -p $MYSQL_VARDIR

SDIR="$LPATH"
SRESULTS="$WORKDIR/sresults"

mkdir -p $SRESULTS

echo "Workdir: $WORKDIR"
echo "Basedir: $MYSQL_BASEDIR"


  ADDR="127.0.0.1"
  RPORT=$(( RANDOM%21 + 10 ))
  RBASE1="$(( RPORT*1000 ))"
  echo "Setting RBASE to $RBASE1"
  RADDR1="$ADDR:$(( RBASE1 + 7 ))"
  LADDR1="$ADDR:$(( RBASE1 + 8 ))"

  RBASE2="$(( RBASE1 + 100 ))"
  RADDR2="$ADDR:$(( RBASE2 + 7 ))"
  LADDR2="$ADDR:$(( RBASE2 + 8 ))"

  SUSER=root
  SPASS=

  node1="${MYSQL_VARDIR}/node1"
  mkdir -p $node1
  node2="${MYSQL_VARDIR}/node2"
  mkdir -p $node2


  pushd ${MYSQL_BASEDIR}/mysql-test/

  set +e 
  perl mysql-test-run.pl \
    --start-and-exit \
    --port-base=$RBASE1 \
    --nowarnings \
    --vardir=$node1 $DBG $MEMOPT $EXTOPTS \
    --mysqld=--innodb_file_per_table  \
    --mysqld=--binlog-format=ROW \
    --mysqld=--wsrep-slave-threads=2 \
    --mysqld=--innodb_autoinc_lock_mode=2 \
    --mysqld=--innodb_locks_unsafe_for_binlog=1 \
    --mysqld=--wsrep-provider=${MYSQL_BASEDIR}/lib/$GVER/libgalera_smm.so \
    --mysqld=--wsrep_cluster_address=gcomm:// \
    --mysqld=--wsrep_sst_receive_address=$RADDR1 \
    --mysqld=--wsrep_node_incoming_address=$ADDR \
    --mysqld=--wsrep_provider_options="gmcast.listen_addr=tcp://$LADDR1" \
    --mysqld=--wsrep_sst_method=$sst_method \
    --mysqld=--wsrep_sst_auth=$SUSER:$SPASS \
    --mysqld=--wsrep_node_address=$ADDR \
    --mysqld=--innodb_flush_method=O_DIRECT \
    --mysqld=--query_cache_type=0 \
    --mysqld=--query_cache_size=0 \
    --mysqld=--innodb_flush_log_at_trx_commit=0 \
    --mysqld=--innodb_buffer_pool_size=500M \
    --mysqld=--innodb_log_file_size=500M \
    --mysqld=--default-storage-engine=InnoDB \
    --mysqld=--core-file \
    --mysqld=--loose-new \
    --mysqld=--sql-mode=no_engine_substitution \
    --mysqld=--loose-innodb \
    --mysqld=--secure-file-priv= \
    --mysqld=--loose-innodb-status-file=1 \
    --mysqld=--skip-name-resolve \
    --mysqld=--socket=$node1/socket.sock \
    --mysqld=--log-error=$WORKDIR/logs/node1.err \
    --mysqld=--log-output=none \
    1st
  set -e
  popd

  sleep 10



    # Sysbench Runs
    ## Prepare/setup
    echo "Sysbench Run: Prepare stage"

   if [[ -n ${BUILTIN_SYSBENCH:-} ]];then 
         /usr/bin/sysbench --test=oltp   --oltp-auto-inc=off --mysql-engine-trx=yes --mysql-table-engine=innodb \
        --oltp-table-size=100000 --mysql-db=test --mysql-user=root \
        --db-driver=mysql --mysql-socket=$node1/socket.sock prepare \
        > $SRESULTS/sysbench_prepare.txt 
    else 
        prepare $node1/socket.sock $WORKDIR/logs/sysbench_prepare.txt 
    fi
 
    $MYSQL_BASEDIR/bin/mysql  -S $node1/socket.sock -u root -e "create database testdb;" || true

  if [[ -n ${DUALTEST:-} ]];then 
    pushd ${MYSQL_BASEDIR}/mysql-test/
    export MYSQLD_BOOTSTRAP_CMD=
    set +e 
    perl mysql-test-run.pl \
        --start-and-exit \
        --port-base=$RBASE2 \
        --nowarnings \
        --vardir=$node2 $DBG $MEMOPT $EXTOPTS \
        --mysqld=--innodb_file_per_table  \
        --mysqld=--binlog-format=ROW \
        --mysqld=--wsrep-slave-threads=2 \
        --mysqld=--innodb_autoinc_lock_mode=2 \
        --mysqld=--innodb_locks_unsafe_for_binlog=1 \
        --mysqld=--wsrep-provider=${MYSQL_BASEDIR}/lib/$GVER/libgalera_smm.so \
        --mysqld=--wsrep_cluster_address=gcomm://$LADDR1 \
        --mysqld=--wsrep_sst_receive_address=$RADDR2 \
        --mysqld=--wsrep_node_incoming_address=$ADDR \
        --mysqld=--wsrep_provider_options="gmcast.listen_addr=tcp://$LADDR2" \
        --mysqld=--wsrep_sst_method=$sst_method \
        --mysqld=--wsrep_sst_auth=$SUSER:$SPASS \
        --mysqld=--wsrep_node_address=$ADDR \
        --mysqld=--innodb_flush_method=O_DIRECT \
        --mysqld=--query_cache_type=0 \
        --mysqld=--query_cache_size=0 \
        --mysqld=--innodb_flush_log_at_trx_commit=0 \
        --mysqld=--innodb_buffer_pool_size=500M \
        --mysqld=--innodb_log_file_size=500M \
        --mysqld=--default-storage-engine=InnoDB \
        --mysqld=--core-file \
        --mysqld=--loose-new \
        --mysqld=--sql-mode=no_engine_substitution \
        --mysqld=--loose-innodb \
        --mysqld=--secure-file-priv= \
        --mysqld=--loose-innodb-status-file=1 \
        --mysqld=--skip-name-resolve \
        --mysqld=--log-error=$WORKDIR/logs/node2.err \
        --mysqld=--socket=$node2/socket.sock \
        --mysqld=--log-output=none \
        1st
    set -e
    popd
  fi

  echo "Sleeping for 10s"
  sleep 10


   if [[ -z ${BUILTIN_SYSBENCH:-} ]];then 
       STABLE="test.sbtest1" 
   else 
       STABLE="test.sbtest" 
   fi

  if [[ -n ${DUALTEST:-} ]];then 
    echo "Before RW testing"

    ver_and_row $node1/socket.sock 
    ver_and_row $node2/socket.sock
  fi

    if [[ ! -e $SDIR/${STEST}.lua ]];then 
        pushd /tmp

        rm $STEST.lua || true
        wget -O $STEST.lua  https://github.com/Percona-QA/sysbench/tree/0.5/sysbench/tests/db/${STEST}.lua
        SDIR=/tmp/
        popd
    fi

   set -x
  if [[ -n ${DUALTEST:-} ]];then 
        ## OLTP RW Run
        echo "Sysbench Run: OLTP RW testing"
        if [[ -n ${BUILTIN_SYSBENCH:-} ]];then 
            /usr/bin/sysbench --num-threads=16 --oltp-auto-inc=off --max-time=$SYSBENCH_DURATION --max-requests=1870000000 \
                --test=oltp --oltp-table-size=100000 --mysql-db=test \
                --mysql-user=root --db-driver=mysql --mysql-socket=$node2/socket.sock \
                run > $SRESULTS/sysbench_rw_run.txt 
        else 
            rw_full "$node1/socket.sock,$node2/socket.sock"  $WORKDIR/logs/sysbench_rw_run.txt 
        fi


        if [[ -n ${BUILTIN_SYSBENCH:-} ]];then 
            echo "Sleeping for 5s"
            sleep 5
            /usr/bin/sysbench --num-threads=16 --oltp-auto-inc=off --max-time=$SYSBENCH_DURATION --max-requests=1870000000 \
                --test=oltp --oltp-table-size=100000 --mysql-db=test \
                --mysql-user=root --db-driver=mysql --mysql-socket=$node1/socket.sock \
                run > $SRESULTS/sysbench_rw_run-1.txt 
        fi
  else 
        ## OLTP RW Run
        echo "Sysbench Run: OLTP RW testing"
        if [[ -n ${BUILTIN_SYSBENCH:-} ]];then 
            /usr/bin/sysbench --num-threads=16 --oltp-auto-inc=off --max-time=$SYSBENCH_DURATION --max-requests=1870000000 \
                --test=oltp --oltp-table-size=100000 --mysql-db=test \
                --mysql-user=root --db-driver=mysql --mysql-socket=$node1/socket.sock \
                run > $SRESULTS/sysbench_rw_run.txt 
        else 
            rw_full "$node1/socket.sock"  $WORKDIR/logs/sysbench_rw_run.txt 
        fi
  fi
  set +x

    ver_and_row $node1/socket.sock 
    ver_and_row $node2/socket.sock
    $MYSQL_BASEDIR/bin/mysql -S $node1/socket.sock  -u root -e "drop database testdb;" || true
    $MYSQL_BASEDIR/bin/mysql -S $node2/socket.sock  -u root -e "drop database test;"


    $MYSQL_BASEDIR/bin/mysqladmin  --socket=$node1/socket.sock -u root shutdown
    $MYSQL_BASEDIR/bin/mysqladmin  --socket=$node2/socket.sock -u root shutdown
