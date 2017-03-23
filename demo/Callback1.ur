con payload = [S = channel string]
table jobtable : (Callback.jobinfo ++ payload)
  PRIMARY KEY Id

sequence jobtable_seq

structure C = Callback.Make(
  struct
    con u = payload
    val t = jobtable
    val s = jobtable_seq

    fun completion (ji : record Callback.jobinfo) =
      c <- oneRowE1 (SELECT J.S AS N FROM jobtable AS J WHERE J.Id = {[ji.Id]});
      j <- CallbackFFI.deref ji.Id;
      send c (CallbackFFI.blobLines (CallbackFFI.stdout j));
      debug ("Completion fired for job #" ^ show ji.Id);
      CallbackFFI.cleanup j;
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

fun stdout (jid:int) : transaction string =
  j <- CallbackFFI.deref jid;
  return (CallbackFFI.blobLines (CallbackFFI.stdout j))

fun jobRender c s (ji : record Callback.jobinfo) : xbody =
  <xml>
    ID {[ji.Id]} Cmd {[ji.Cmd]} ExitCode {[ji.ExitCode]}
    <p>Hint {[ji.Hint]}</p>
    <p>Stdout:
    <p>
      <active code={
        spawn(x <- recv c; set s <xml>{[x]}</xml>);
        return <xml/>
      }/>
      <dyn signal={ signal s }/>
    </p>
    </p>
  </xml>

fun create1 {} : transaction (int*xbody) =
  c <- channel;
  j <- C.create( C.shellCommand "sleep 5; echo DONE;" ++ C.defaultIO ) {S = c};
  x <- C.monitorX C.defaultRender j;
  jid <- CallbackFFI.refM j;
  return (jid,x)

fun create2 {} : transaction (int*xbody) =
  s <- source <xml/>;
  c <- channel;
  j <- C.create( C.shellCommand "read p1; read p2; sleep 60; echo Parameters are $p1 $p2;"
    ++ {
      Stdin = Callback.Chunk (textBlob "33\n42\n",True)
    , Stdin_sz = 100
    , Stdout_sz = 100
    , Stdout_wrap = False
    }) {S = c};
  x <- C.monitorX (jobRender c s) j;
  jid <- CallbackFFI.refM j;
  return (jid,x)

fun main {} : transaction page = template (
  sjid <- source 0;
  sdisp <- source <xml/>;

  return <xml>
    <p>Callback Demo</p>

    <button onclick={fn _ =>
      res <- rpc(create1 {});
      set sjid res.1;
      set sdisp res.2;
      return {}
    }>
      Create delay task
    </button>

    <button onclick={fn _ =>
      res <- rpc(create2 {});
      set sjid res.1;
      set sdisp res.2;
      return {}
    }>
      Create input task
    </button>

    <button onclick={fn _ =>
      jid <- get sjid;
      rpc(terminate jid)
    }>
      Terminate task
    </button>

    <p>
    <dyn signal={ signal sdisp }/>
    </p>
  </xml>
  )

