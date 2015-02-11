{-# LANGUAGE ScopedTypeVariables #-}
module Cake_Callback where

import Development.Cake3
import Development.Cake3.Ext.UrWeb
import Cake_Callback_P

lib = uwlib (file "lib.urp") $ do
  ffi (file "CallbackFFI.urs")
  include (file "CallbackFFI.h")
  src (file "CallbackFFI.cpp", "-std=c++11", "-lstdc++")
  safeGet "Callback/Default/callback"
  safeGet "CallbackNotify/Default/C/callback"
  ur (sys "list")
  ur (file "Callback.ur", file "Callback.urs")
  ur (file "CallbackNotify.ur", file "CallbackNotify.urs")
  ur (file "CallbackNotify2.ur", file "CallbackNotify2.urs")

demo = uwapp "-dbms postgres" (file "demo/Demo2.urp") $ do
  let d = file "demo/Demo2.ur"
  database ("dbname="++(takeBaseName d))
  safeGet ((takeBaseName d)++"/main")
  safeGet ((takeBaseName d)++"/monitor")
  allow env "PING"
  sql (d.="sql")
  library lib
  ur (sys "list")
  ur (sys "char")
  ur (sys "string")
  ur (pair d)

tests = do
  let tf = map file [
              "test/Stress1.ur"
            , "test2/Simple1.ur"
            , "test2/Stdout.ur"
            , "test2/Stress.ur"
            , "test2/Notify.ur"
            ]
  forM tf $ \t -> do
    uwapp "-dbms postgres" (t.="urp") $ do
      let sg x = safeGet ((takeBaseName t) ++ "/" ++ x)
      debug
      allow url "http://code.jquery.com/ui/1.10.3/jquery-ui.js"
      allow mime "text/javascript"
      allow mime "text/css"
      allow mime "image/jpeg"
      allow mime "image/png"
      allow mime "image/gif"
      database ("dbname="++(takeBaseName t))
      sg "main"
      sg "job_monitor"
      sg "src_monitor"
      sg "job_start"
      sg "finished"
      sg "cleanup"
      sg "monitor"
      sg "run"
      sg "C/callback"
      sg "C/C/callback"
      sg "cnt"
      sg "Find/C/callback"
      sg "Cat/C/callback"
      sg "viewsrc"
      sg "status"
      sg "lastline"
      sg "longrunning"
      sql (t.="sql")
      library lib
      ur (sys "list")
      ur (sys "string")
      ur (file "test2/Templ.ur")
      ur t

main = writeMake (file "Makefile") $ do

  rule $ do
    phony "lib"
    depend lib

  let mkdb t = rule $ do
                let sql = urpSql (toUrp t)
                let dbn = takeBaseName sql
                shell [cmd|dropdb --if-exists $(string dbn)|]
                shell [cmd|createdb $(string dbn)|]
                shell [cmd|psql -f $(sql) $(string dbn)|]
                shell [cmd|touch @(sql.="db")|]

  d <- demo
  rule $ do
    phony "demo"
    depend (mkdb d)

  ts <- tests
  rule $ do
    phony "all"
    depend ts
    depend (map mkdb ts)
    depend d
    depend (mkdb d)


