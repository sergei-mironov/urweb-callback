structure T = Templ
structure C = Callback.Default

fun monitor (jr:C.jobref) : transaction page = T.template (
  j <- C.get jr;
  return <xml>{[j.Stdout]}</xml>)

val max = 40

fun longrunning (k:int) : transaction page = T.template (
  x <- C.abortMore max;
  jr <- C.create (C.shellCommand ("sleep " ^ (show k)));
  redirect (url (monitor jr)))

fun main {} : transaction page = T.template (
  x <- C.abortMore max;
  jr <- C.create (C.shellCommand ("for i in `seq 1 1 20` ; do sleep 0.1; echo -n . ; done"));
  redirect (url (monitor jr)))

fun cnt {} : transaction page = T.template (
  x <- C.abortMore max;
  return <xml>{[x]}</xml>)
