#!/bin/sh

PORT=8080
if test -n "$1" ; then
  PORT=$1
fi

URL="http://localhost:$PORT/Stress/viewsrc/.2E.2Ftest.2FTest6.2Eur"

for i in `seq 1 1 50` ; do

  wget -S -O -  "$URL" /dev/null &

done
