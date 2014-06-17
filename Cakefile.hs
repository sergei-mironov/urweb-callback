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
    safeGet "Callback.ur" "Default/callback"
    safeGet "CallbackNotify.ur" "C/callback"
    ur (sys "list")
    ur (pair "Callback.ur")
    ur (pair "CallbackNotify.ur")
    ur (pair "CallbackNotify2.ur")

  let tests = [ "test/Stress.ur"
              , "test2/Simple1.ur"
              , "test2/Stdout.ur"
              , "test2/Stress.ur"
              -- , "test/Test1.urp"
              -- , "test/Test2.urp"
              -- , "test/Test3.urp"
              -- , "test/Test4.urp"
              -- , "test/Test5.urp"
              -- , "test/Test6.urp"
              -- , "test/Test8.urp"
              ]

  ts <- forM tests $ \t -> do
    uwapp "-dbms postgres" (t.="urp") $ do
      debug
      allow url "http://code.jquery.com/ui/1.10.3/jquery-ui.js";
      allow mime "text/javascript";
      allow mime "text/css";
      allow mime "image/jpeg";
      allow mime "image/png";
      allow mime "image/gif";
      database ("dbname="++(takeBaseName t))
      safeGet (t.="ur") "main"
      safeGet (t.="ur") "job_monitor"
      safeGet (t.="ur") "src_monitor"
      safeGet (t.="ur") "job_start"
      safeGet (t.="ur") "finished"
      safeGet (t.="ur") "cleanup"
      safeGet (t.="ur") "monitor"
      safeGet (t.="ur") "run"
      safeGet (t.="ur") "C/callback"
      safeGet (t.="ur") "cnt"
      safeGet (t.="ur") "Find/C/callback"
      safeGet (t.="ur") "Cat/C/callback"
      safeGet (t.="ur") "viewsrc"
      safeGet (t.="ur") "status"
      safeGet (t.="ur") "lastline"
      safeGet (t.="ur") "longrunning"
      sql (t.="sql")
      library l
      ur (sys "list")
      ur (sys "string")
      ur (single "test2/Templ.ur")
      ur (single t)


  d <- uwapp "-dbms postgres" "demo/Demo.urp" $ do
    let demo = "demo/Demo.ur"
    allow url "http://code.jquery.com/ui/1.10.3/jquery-ui.js";
    allow mime "text/javascript";
    allow mime "text/css";
    allow mime "image/jpeg";
    allow mime "image/png";
    allow mime "image/gif";
    database ("dbname="++(takeBaseName demo))
    safeGet demo "main"
    safeGet demo "job_monitor"
    safeGet demo "src_monitor"
    safeGet demo "job_start"
    safeGet demo "C/callback"
    safeGet demo "Find/C/callback"
    safeGet demo "Cat/C/callback"
    safeGet demo "viewsrc"
    safeGet demo "status"
    sql (demo.="sql")
    library l
    ur (sys "list")
    ur (sys "string")
    ur (pair demo)

  dbs <- forM (d:ts) $ \t -> rule $ do
    let sql = urpSql (toUrp t)
    let dbn = takeBaseName sql
    shell [cmd|dropdb --if-exists $(string dbn)|]
    shell [cmd|createdb $(string dbn)|]
    shell [cmd|psql -f $(sql) $(string dbn)|]
    shell [cmd|touch @(sql.="db")|]

  rule $ do
    phony "lib"
    depend l

  rule $ do
    phony "all"
    depend ts
    depend d
    depend dbs

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

