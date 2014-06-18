structure C = Callback.Default

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun monitor (jr:C.jobref) : transaction page = template (
  s <- source "";
  let
    fun getout jr = j <- C.get jr; return j.Stdout
    fun loop {} = o <- rpc (getout jr); set s o; sleep 1000; loop {}
  in
    return
      <xml>
        <active code={spawn (loop {}); return <xml/>} />
        <dyn signal={v<-signal s; return <xml><pre>{[v]}</pre></xml>}/>
      </xml>
  end)

fun main {} : transaction page =
  x <- C.abortMore 20;
  jr <- C.create (C.shellCommand ("ping www.google.com"));
  redirect (url (monitor jr))

