
structure C = Callback.Default
structure T = Templ

fun monitor (jr:C.jobref) : transaction page = T.template (
  j <- C.get jr;
  return <xml>{[j.Stdout]}</xml>)

val max = 40

fun main {} : transaction page = T.template (
  x <- C.abortMore max;
  jr <- C.create (C.shellCommand ("find /sys"));
  redirect (url (monitor jr)))

fun cnt {} : transaction page = T.template (
  x <- C.abortMore max;
  return <xml>{[x]}</xml>)
