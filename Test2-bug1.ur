
fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun finished (j:Callback.job) : transaction page =
  return <xml/>

and handler (s:{UName:string}) : transaction page = 
  let

    (* One have to move the monitor to the toplevel to make bug gone *)
    fun monitor (j:Callback.job) = template (
      f <- form {};
      return
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
        </xml>)

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
    
fun main {} : transaction page = template (
  f <- form {};
  return 
    <xml>
      Welcome
      <hr/>
      {f}
    </xml>)
  
