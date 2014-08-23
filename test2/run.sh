#!/bin/sh

msg() { echo "$TEST $@" >&2 ; echo "$TEST $@" ; }
die() { msg "$@" ; exit 1 ; }

PORT=9090
U=127.0.0.1:$PORT
WGET_ARGS="-t 1 -T 3 -O - -S "
TEST="run.sh:"
TD=`dirname $0`
silent() { $@ >/dev/null 2>&1 ; }
noerr() { $@ 2>/dev/null ; }
tolog() { $@ 2>&1 ; }

while test -n "$1" ; do
  case $1 in
    fixtw)
      echo 5 > /proc/sys/net/ipv4/tcp_fin_timeout
      exit 0
      ;;
    -p)
      PORT=$2
      shift
      ;;
    -h|--help)
      echo "run.sh [-p PORT] [fixtw]" >&2
      exit 1
      ;;
  esac
  shift
done

end() {
  silent killall sleep
  if test -n "$PID" ; then
    msg Killing $PID
    silent kill $PID ||
     die "Failed to kill PID $PID"
    unset PID
  fi
  TEST="run.sh:"
}

begin() {
  end
  TEST="`basename $1`:"
  $1 -p $PORT >$1.log 2>&1 &
  PID=$!
  trap end EXIT
  sleep 0.5
}

#
# MAIN PART
#


# Force re-creation of the databases
cd $TD
rm *db
make -C .. || die "Make failed"

{
date
begin "./Simple1.exe"

  KEY=787
  
  msg "PID is $PID"
  msg "Starting wget pack"
  for i in `seq 1 1 30` ; do
    wget $WGET_ARGS $U/Simple1/main/$KEY >/dev/null 2>&1 || {
      ret=$?
      if expr $i '<' 10 >/dev/null ; then
        die "Server denied too early (i=$i, ret=$ret)"
      fi
    }
  done

  msg "Checking job count (ps fax)"
  ps fax -o pid,ppid,args | tolog grep $PID
  nsleep=`ps fax -o pid,ppid,args | grep $PID | grep $KEY | wc -l`
  if test "$nsleep" != "20" ;then
    die "Invalid number of sleep childs ($nsleep)"
  fi

  msg "Checking job count (API)"
  noerr wget $WGET_ARGS $U/Simple1/cnt | tolog grep '<body>20</body>' ||
    die "Invalid number of jobs running"

end

begin "./Stdout.exe"

  tolog wget $WGET_ARGS $U/Stdout/main/aaa/bbb
  sleep 0.5
  L=/tmp/uwcb-stdout.out

  msg "Checking multy-line"
  noerr wget $WGET_ARGS $U/Stdout/monitor >$L
  tolog grep '<body>aaa$' $L || die
  tolog grep '^bbb</body>' $L || die

  msg "Checking lastline"
  noerr wget $WGET_ARGS $U/Stdout/lastline >$L
  tolog grep '<body>bbb</body>' $L || die

end

begin "./Stress.exe"

  msg "Starting stress-test with 1 long-running job"

  KEY=2023
  tolog wget $WGET_ARGS $U/Stress/longrunning/$KEY

  for i in `seq 1 1 2000` ; do
    case $i in
      *500|*000) msg "Creating session #$i" ;;
    esac
    (
      tolog wget $WGET_ARGS $U/Stress/main
    ) &
    sleep 0.01
  done

  msg "Done stress testing"
  
  for i in `seq 1 1 20` ; do

    noerr wget $WGET_ARGS $U/Stress/cnt | grep '<body>1</body>' && {
      msg "Got zero"
      break;
    }

    if test "$i" = "10" ; then
      die "Resource leak"
    else
      sleep 0.5
    fi
  done

  nsleep=`ps fax -o pid,ppid,args | grep $PID | grep $KEY | wc -l`
  if test "$nsleep" != "1" ;then
    die "Invalid number of sleep childs ($nsleep)"
  fi

end

msg SUCCESS

} >test.log
