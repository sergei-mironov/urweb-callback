module Cakefile where

import Development.Cake3
import Development.Cake3.Ext.UrWeb
import Cakefile_P

instance IsString File where fromString = file

project = do

  l <- uwlib "lib.urp" $ do
    ffi "CallbackFFI.urs"
    include "CallbackFFI.h"
    csrc' "CallbackFFI.cpp" "-std=c++11" "-lstdc++"
    ur (pair "Callback.ur")

  let tests = [ "test/Test1.urp"
              , "test/Test2.urp"
              , "test/Test3.urp"
              , "test/Test4.urp"
              , "test/Test5.urp"
              ]

  ts <- forM tests $ \t -> do
    uwapp "-dbms postgres" t $ do
      allow url "http://code.jquery.com/ui/1.10.3/jquery-ui.js";
      allow mime "text/javascript";
      allow mime "text/css";
      allow mime "image/jpeg";
      allow mime "image/png";
      allow mime "image/gif";
      allow env "USER";
      database ("dbname="++(takeBaseName t))
      safeGet (t.="ur") "main"
      safeGet (t.="ur") "job_monitor"
      safeGet (t.="ur") "job_start"
      safeGet (t.="ur") "finished"
      safeGet (t.="ur") "cleanup"
      safeGet (t.="ur") "monitor"
      safeGet (t.="ur") "run"
      safeGet (t.="ur") "C/callback"
      sql (t.="sql")
      library l
      debug
      ur (sys "list")
      ur (pair (t.="ur"))

  dbs <- forM ts $ \t -> rule $ do
    let sql = urpSql (toUrp t)
    let dbn = takeBaseName sql
    shell [cmd|dropdb --if-exists $(string dbn)|]
    shell [cmd|createdb $(string dbn)|]
    shell [cmd|psql -f $(sql) $(string dbn)|]
    shell [cmd|touch @(sql.="db")|]

  rule $ do
    phony "all"
    depend ts
    depend dbs

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

