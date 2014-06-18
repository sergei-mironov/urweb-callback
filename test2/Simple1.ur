structure C = Callback.Default
structure T = Templ

fun monitor (jr:C.jobref) : transaction page = T.template (
  j <- C.get jr;
  return <xml>ExitCode : {[j.ExitCode]}</xml>)

fun main (i:int) : transaction page = T.template (
  x <- C.abortMore 20;
  jr <- C.create (C.shellCommand ("sleep " ^ show i));
  redirect (url (monitor jr)))

fun cnt {} : transaction page = T.template (
  x <- C.abortMore 20;
  return <xml>{[x]}</xml>)
