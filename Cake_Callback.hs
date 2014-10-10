module Cake_Callback where

import Development.Cake3
import Development.Cake3.Ext.UrWeb
import Cake_Callback_P

lib_callback = do
  uwlib (file "lib.urp") $ do
    ffi (file "CallbackFFI.urs")
    include (file "CallbackFFI.h")
    csrc' (file "CallbackFFI.cpp") "-std=c++11" "-lstdc++"
    safeGet (file "Callback.ur") "Default/callback"
    safeGet (file "CallbackNotify.ur") "Default/C/callback"
    ur (sys "list")
    ur (pair (file "Callback.ur"))
    ur (pair (file "CallbackNotify.ur"))
    ur (pair (file "CallbackNotify2.ur"))

demo_callback = do
  l <- lib_callback
  uwapp "-dbms postgres" (file "demo/Demo2.urp") $ do
    let demo = file "demo/Demo2.ur"
    database ("dbname="++(takeBaseName demo))
    safeGet demo "main"
    safeGet demo "monitor"
    allow env "PING"
    sql (demo.="sql")
    library l
    ur (sys "list")
    ur (sys "char")
    ur (sys "string")
    ur (pair demo)

project = do
  l <- lib_callback
  let tests = map file [
                "test/Stress1.ur"
              , "test2/Simple1.ur"
              , "test2/Stdout.ur"
              , "test2/Stress.ur"
              , "test2/Notify.ur"
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
      safeGet (t.="ur") "C/C/callback"
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
      ur (single (file "test2/Templ.ur"))
      ur (single t)

  d <- demo_callback

  let mkdb t = rule $ do
                let sql = urpSql (toUrp t)
                let dbn = takeBaseName sql
                shell [cmd|dropdb --if-exists $(string dbn)|]
                shell [cmd|createdb $(string dbn)|]
                shell [cmd|psql -f $(sql) $(string dbn)|]
                shell [cmd|touch @(sql.="db")|]

  rule $ do
    phony "demo"
    depend (mkdb d)

  rule $ do
    phony "lib"
    depend l

  rule $ do
    phony "all"
    depend ts
    depend (map mkdb ts)
    depend d
    depend (mkdb d)

main = do
  writeMake (file "Makefile") (project)
  writeMake (file "Makefile.devel") (selfUpdate >> project)

