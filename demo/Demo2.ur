structure C = Callback.Default

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

val cmd = "ping -c 15"

fun monitor (jr:C.jobref) : transaction page = template (
  s <- source "";
  let
    fun getout jr = j <- C.get jr; return (C.lastLines 8 j.Stdout)
    fun loop {} = o <- rpc (getout jr); set s o; sleep 1000; loop {}
  in
    return
      <xml>
        <active code={spawn (loop {}); return <xml/>} />
        <dyn signal={v<-signal s; return <xml><pre>{[v]}</pre></xml>}/>
      </xml>
  end)

fun ping frm =
  x <- C.abortMore 20;
  s <- C.checkString (String.all (fn c => Char.isAlnum c || #"." = c)) frm.IP;
  jr <- C.create (C.shellCommand (cmd ^ " " ^ s));
  redirect (url (monitor jr))

fun main {} : transaction page = template (
  return <xml>
    <form>
      <p>Who do you want to ping today?</p>
      <p>{[cmd]} <textbox{#IP}/></p>
      <submit action={ping}/>
    </form>
  </xml>)

