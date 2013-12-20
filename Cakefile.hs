module Cakefile where

import Development.Cake3
import Development.Cake3.Ext.UrWeb
import Cakefile_P

instance IsString File where fromString = file

project = do

  a <- uwapp "-dbms sqlite" "Test.urp" $ do
    ur (sys "option")
    ur (pair "Test.ur")
    safeGet "Test/main"
    safeGet "Test/main_ru"
    safeGet "Test/main_en"
    safeGet "Test/handler_get"
    safeGet "Test/job_start"
    allow mime "text/javascript"
    allow mime "text/css"
    database "dbname=Test"
    sql "Test.sql"
    debug
    ffi "Callback.urs"
    include "Callback.h"
    csrc' "Callback.cpp" "-std=c++11" "-lstdc++"

  a2 <- uwapp "-dbms sqlite" "Test2.urp" $ do
    ur (pair "Test2.ur")
    safeGet "Test2/main"
    allow mime "text/javascript"
    allow mime "text/css"
    database "dbname=Test2"
    sql "Test2.sql"
    debug
    ffi "Callback.urs"
    include "Callback.h"
    csrc' "Callback.cpp" "-std=c++11" "-lstdc++"

  rule $ do
    phony "clean"
    unsafeShell [cmd|rm -rf .cake3 $(tempfiles a)|]

  rule $ do
    phony "all"
    depend a
    depend a2

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

