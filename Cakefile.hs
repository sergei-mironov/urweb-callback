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
    allow mime "text/javascript"
    allow mime "text/css"
    database "dbname=Test"
    sql "Test.sql"
    debug
    ffi "Callback.urs"
    include "Callback.h"
    link "Callback.o"

  rule $ do
    phony "run"
    shell [cmd|$(a)|]

  rule $ do
    phony "clean"
    unsafeShell [cmd|rm -rf .cake3 $(tempfiles a)|]

  rule $ do
    phony "all"
    depend a

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

