table t : { Id : int , Chan : channel string }

val gj = Callback.deref
val ref = Callback.ref

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun finished (jr:Callback.jobref) : transaction page =
  debug "finished callback has been called";
  j <- Callback.deref jr;
  s <- query1 (SELECT * FROM t WHERE t.Id = {[jr]}) (fn r s =>
    ch <- (return r.Chan);
    send ch (Callback.stdout j);
    return (s+1)) 0;
  debug ("Stdout has been sent to a " ^ (show s) ^ " clients ");
  return <xml/>

fun monitor (jr:Callback.jobref) =
  j <- Callback.deref jr;
  ch <- channel;
  dml(INSERT INTO t (Id,Chan) VALUES ({[ref j]},{[ch]}));
  f <- form {};
  s <- source <xml>{[Callback.stdout j]}</xml>;
  let
    fun check {} = 
      stdout <- recv ch;
      alert stdout;
      set s <xml>{[stdout]}</xml>;
      check {}
  in
    return
      <xml>
        <head/>
        <body onload={check {}}>
          Job : {[jr]}
          <br/>
          Pid : {[Callback.pid j]}
          <br/>
          ExitCode : {[Callback.exitcode j]}
          <br/>
          <dyn signal={signal s}/>
          <br/>
          (* Errors:  {[Callback.errors j]} *)
          (* <hr/> *)
          {f}
          <br/>
          <a link={monitor jr}>Refresh</a>
          <a link={cleanup jr}>Cleanup job</a>
        </body>
      </xml>
    end

and handler (s:{UName:string}) : transaction page = 
  let

    fun start {} : transaction xbody =
      j <- Callback.create s.UName "" 100;
      Callback.run j (url (finished (ref j)));
      redirect (url (monitor (ref j)))

    fun retry {} : transaction xbody = (
      f <- form {};
      return
        <xml>
          String is empty, try again
          <hr/>
          {f}
        </xml>)
  in
    template (
      case s.UName = "" of
          True => retry {}
        | False => start {})
  end

and form {} : transaction xbody = 
  return
    <xml>
      <form>
        Enter command: <textbox{#UName}/><br/>
        <submit action={handler}/>
      </form>
    </xml>

and cleanup (jr:Callback.jobref) = template (
  o <- Callback.tryDeref jr;
  case o of
    Some j =>
      Callback.cleanup j;
      f <- form {};
      return 
        <xml>
          Job {[Callback.ref j]} is no more
          <hr/>
          {f}
        </xml>
    | None =>
      return <xml>No such job!</xml>)

    
fun main {} : transaction page = template (
  f <- form {};
  return 
    <xml>
      Welcome
      <hr/>
      {f}
    </xml>)
  
