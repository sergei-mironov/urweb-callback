module Cakefile where

import Development.Cake3
import Development.Cake3.Ext.UrWeb
import Cakefile_P

instance IsString File where fromString = file

project = do
  l <- uwlib "lib.urp" $ do
    ffi "Callback.urs"
    include "Callback.h"
    csrc' "Callback.cpp" "-std=c++11" "-lstdc++"

  a <- uwapp "-dbms sqlite" "Test.urp" $ do
    ur (sys "option")
    ur (pair "Test.ur")
    safeGet "Test.ur" "main"
    safeGet "Test.ur" "main_ru"
    safeGet "Test.ur" "job_monitor"
    safeGet "Test.ur" "main_en"
    safeGet "Test.ur" "handler_get"
    safeGet "Test.ur" "job_start"
    allow mime "text/javascript"
    allow mime "text/css"
    database "dbname=Test"
    sql "Test.sql"
    library l
    debug

  a2 <- uwapp "-dbms sqlite" "Test2.urp" $ do
    ur (pair "Test2.ur")
    safeGet "Test2.ur" "main"
    safeGet "Test2.ur" "finished"
    safeGet "Test2.ur" "monitor"
    safeGet "Test2.ur" "cleanup"
    safeGet "Test2.ur" "sendch"
    allow mime "text/javascript"
    allow mime "text/css"
    database "dbname=Test2.db"
    sql "Test2.sql"
    library l
    debug

  db2 <- rule $do
    let db = file "Test2.db"
    shell [cmd|-rm @db|]
    shell [cmd|sqlite3 @db < $(urpSql (toUrp a2)) |]

  rule $ do
    phony "clean"
    unsafeShell [cmd|rm -rf .cake3 $(tempfiles a)|]

  rule $ do
    phony "all"
    depend a
    depend a2
    depend db2

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

