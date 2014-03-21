table t : { Id : int , Chan : channel string }

val gj = CallbackFFI.deref
val ref = CallbackFFI.ref

sequence jobrefs

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun finished (jr:CallbackFFI.jobref) : transaction page =
  debug "finished CallbackFFI has been called";
  j <- CallbackFFI.deref jr;
  s <- query1 (SELECT * FROM t WHERE t.Id = {[jr]}) (fn r s =>
    ch <- (return r.Chan);
    send ch (CallbackFFI.stdout j);
    return (s+1)) 0;
  debug ("Stdout has been sent to a " ^ (show s) ^ " clients ");
  return <xml/>

fun monitor (jr:CallbackFFI.jobref) =
  j <- CallbackFFI.deref jr;
  ch <- channel;
  dml(INSERT INTO t (Id,Chan) VALUES ({[ref j]},{[ch]}));
  f <- form {};
  s <- source <xml> == {[CallbackFFI.stdout j]} == </xml>;
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
          Pid : {[CallbackFFI.pid j]}
          <br/>
          ExitCode : {[CallbackFFI.exitcode j]}
          <br/>
          <dyn signal={signal s}/>
          <br/>
          (* Errors:  {[CallbackFFI.errors j]} *)
          (* <hr/> *)
          {f}
          <br/>
          <a link={monitor jr}>Refresh</a>
          <a link={cleanup jr}>Cleanup job</a>
        </body>
      </xml>
    end

and form {} : transaction xbody = 
  let
    fun handler (s:{UName:string}) : transaction page = 
      let

        fun start {} : transaction xbody =
          jr <- nextval jobrefs;
          j <- CallbackFFI.create s.UName 100 jr;
          CallbackFFI.setCompletionCB j (Some (url (finished (ref j))));
          CallbackFFI.pushStdinEOF j;
          CallbackFFI.run j;
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
  in
  return
    <xml>
      <form>
        Enter command: <textbox{#UName}/><br/>
        <submit action={handler}/>
      </form>
    </xml>
  end

and cleanup (jr:CallbackFFI.jobref) = template (
  o <- CallbackFFI.tryDeref jr;
  case o of
    Some j =>
      CallbackFFI.cleanup j;
      f <- form {};
      return 
        <xml>
          Job {[CallbackFFI.ref j]} is no more
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
  
