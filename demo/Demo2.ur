structure C = Callback.Default

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun monitor (jr:C.jobref) : transaction page = template (
  j <- C.get jr;
  return <xml><pre>{[j.Stdout]}</pre></xml>)

fun main {} : transaction page =
  x <- C.abortMore 20;
  jr <- C.create (C.shellCommand ("ping www.google.com"));
  redirect (url (monitor jr))

