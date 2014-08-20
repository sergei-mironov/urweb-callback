structure CB = Callback
structure C = Callback.Default

fun needenv v =
  e <- getenv (blessEnvVar v);
  case e of
    |Some x => return x
    |None => error <xml>Env var {[v]} is not set</xml>

task initialize = fn _ =>
  _ <- needenv "PING";
  return {}

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun monitor (jr:C.jobref) : transaction page = template (
  s <- source ("", "");
  let
    fun getout jr = j <- C.get jr; return (CB.lastLines 8 j.Stdout, CB.lastLines 8 j.Stderr)
    fun loop {} = o <- rpc (getout jr); set s o; sleep 1000; loop {}
  in
    j <- C.get jr;
    return
      <xml>
        <h1>Executing {[j.Cmd]}</h1>
        <hr/>
        <active code={spawn (loop {}); return <xml/>} />
        <dyn signal={
          (o,e)<-signal s;
          return <xml>
            <div style="height:300px;">
              <h3>Stdout</h3>
              <pre>{[o]}</pre>
            </div>
            <hr/>
            <div style="height:300px;">
              <h3>Stderr</h3>
              <pre>{[e]}</pre>
            </div>
            <hr/>
          </xml>
        }/>
      </xml>
  end)

fun ping frm =
  ping <- needenv "PING";
  x <- C.abortMore 20;
  jr <- C.create (C.absCommand ping ("-c" :: "15" :: frm.IP :: []));
  redirect (url (monitor jr))

fun main {} : transaction page = template (
  return <xml>
    <form>
      <p>Who do you want to ping today?</p>
      <p>ping -c 15 <textbox{#IP}/></p>
      <submit action={ping}/>
    </form>
  </xml>)

