table jobtable : (Callback.jobinfo)
  PRIMARY KEY Id

sequence jobtable_seq

structure C = Callback.Make(
  struct
    con u = []
    val t = jobtable
    val s = jobtable_seq

    fun completion (ji : record Callback.jobinfo) =
      return {}
  end
)

fun terminate (jid:int) : transaction {} =
  j <- CallbackFFI.deref jid;
  CallbackFFI.terminate j

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun main {} : transaction page = template (
  j <- C.create( C.shellCommand "sleep 5; echo DONE;" ++ C.defaultIO ) {};
  x <- C.monitorX C.defaultRender j;
  jid <- CallbackFFI.refM j;
  return <xml>
    <p>Callback template</p>
    <button onclick={fn _ => rpc(terminate jid)} >Terminate</button>
    {x}
  </xml>
  )

