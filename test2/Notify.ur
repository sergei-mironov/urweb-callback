structure CB = Callback
structure C = CallbackNotify.Default

fun workaround_bug_180 {} =
  dummy <- channel; send dummy 0

fun search (p:string) : transaction xbody =
  x <- C.abortMore 20;
  jr <- C.create (C.shellCommand ("sleep 2 ; find " ^ p ^ " -maxdepth 2"));
  C.monitorX jr (fn j =>
    case j.ExitCode of
      |Some _ => <xml><pre>{[j.Stdout]}</pre></xml>
      |None => <xml>Searching...</xml>)

fun main {} : transaction page =
  workaround_bug_180 {};
  s <- source <xml/>;
  return <xml>
    <head/>
    <body>
      <button value="Search files" onclick={fn _ =>
        x <- rpc(search ".");
        set s x
      }/>
      <hr/>
      <dyn signal={signal s}/>
    </body>
  </xml>

