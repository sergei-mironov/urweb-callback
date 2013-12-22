val gj = Callback.deref
val ref = Callback.ref

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun finished (j:Callback.jobref) : transaction page =
  return <xml/>

fun monitor (jr:Callback.jobref) = template (
  j <- return (Callback.deref jr);
  f <- form {};
  x <- (return
    <xml>
      Job : {[jr]}
      <br/>
      Pid : {[Callback.pid j]}
      <br/>
      ExitCode : {[Callback.exitcode j]}
      <br/>
      Stdout:  {[Callback.stdout j]}
      <br/>
      Errors:  {[Callback.errors j]}
      <hr/>
      {f}
      <br/>
      <a link={cleanup jr}>Cleanup job</a>
    </xml>);
  return x)

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
  o <- return (Callback.tryDeref jr);
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
  
