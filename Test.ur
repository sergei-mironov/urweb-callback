
fun handler_get (c:int) : transaction page = 
  debug ("handler called with args: " ^ (show c));
  return <xml/>

fun handler_post (s:{UName:string}) : transaction page = 
  debug ("handler called with args: " ^ (s.UName));
  return <xml/>

fun main {} : transaction page = 
  Callback.call (url (handler_get 33));
  (* Callback.call (url (handler_post {UName="blabla"})); *)
  return
    <xml>
      <head/>
      <body>
        <form>
          User Name: <textbox{#UName}/><br/>
          <submit action={handler_post}/>
        </form>
      </body>
    </xml>
    
