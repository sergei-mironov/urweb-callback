fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun finished (j:Callback.jobref) : transaction page =
  return <xml/>

fun monitor (j:Callback.jobref) = template (
  f <- form {};
  x <- (return
    <xml>
      Job : {[j]}
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
      <a link={cleanup j}>Cleanup job</a>
    </xml>);
  (* Callback.cleanup j; *)
  return x)

and handler (s:{UName:string}) : transaction page = 
  let

    fun start {} : transaction xbody =
      j <- Callback.create s.UName "" 100;
      Callback.run j (url (finished j));
      redirect (url (monitor j))

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

and cleanup (j:Callback.jobref) = template (
  Callback.cleanup j;
  f <- form {};
  return 
    <xml>
      Job is no more
      <hr/>
      {f}
    </xml>)

    
fun main {} : transaction page = template (
  f <- form {};
  return 
    <xml>
      Welcome
      <hr/>
      {f}
    </xml>)
  
