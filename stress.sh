#!/bin/sh

URL="http://localhost:8090/Stress/viewsrc/.2E.2Ftest.2FTest6.2Eur"

for i in `seq 1 1 50` ; do 

  wget -S -O -  "$URL" /dev/null &

done
