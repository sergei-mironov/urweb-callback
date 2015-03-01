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

(demo, demo_db) = uwapp_postgres (file "demo/Demo2.urp") $ do
  let d = file "demo/Demo2.ur"
  safeGet ((takeBaseName d)++"/main")
  safeGet ((takeBaseName d)++"/monitor")
  allow env "PING"
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

  (flip map) tf $ \t -> do
    uwapp_postgres (t.="urp") $ do
      let sg x = safeGet ((takeBaseName t) ++ "/" ++ x)
      debug
      allow url "http://code.jquery.com/ui/1.10.3/jquery-ui.js"
      allow mime "text/javascript"
      allow mime "text/css"
      allow mime "image/jpeg"
      allow mime "image/png"
      allow mime "image/gif"
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
      library lib
      ur (sys "list")
      ur (sys "string")
      ur (file "test2/Templ.ur")
      ur t

main = writeDefaultMakefiles $ do

  rule $ do
    phony "lib"
    depend lib

  rule $ do
    phony "demo"
    depend demo
    depend demo_db

  rule $ do
    phony "all"
    depend (map fst tests)
    depend (map snd tests)
    depend demo
    depend demo_db


