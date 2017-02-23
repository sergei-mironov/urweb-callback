
structure FFI = CallbackFFI

type jobref = FFI.jobref

con jobinfo = [
    Id = int
  , ExitCode = option int
  , Cmd = string
  , Hint = string
  ]

(* Blob with possible end-of-file marker *)
datatype buffer = Chunk of blob * bool

(* Job options *)
con jobargs = [
    Cmd = string
  , Args = list string
  , Stdin = buffer
  , Stdin_sz = int
  , Stdout_sz = int
  , Stdout_wrap = bool
  ]

task initialize = fn _ =>
  FFI.initialize 4;
  return {}

fun create_
    (jid:int)
    (ja:record jobargs)
    (cb:option url)
    : transaction FFI.job =

  j <- FFI.create ja.Cmd ja.Stdout_wrap ja.Stdin_sz ja.Stdout_sz jid;
  _ <- List.mapM (FFI.pushArg j) ja.Args;
  FFI.setCompletionCB j cb;
  _ <- (case ja.Stdin of
    |Chunk (b,True) => (
      FFI.pushStdin j b;
      FFI.pushStdinEOF j;
      return {}
      )
    |Chunk (b,False) => (
      FFI.pushStdin j b;
      return {}
      ));

  return j

fun shellCommand (s:string) = {
    Cmd = "/bin/sh"
  , Args = "-c" :: s :: []
  }

val defaultIO = {
    Stdin = Chunk (textBlob "",True)
  , Stdin_sz = 0
  , Stdout_sz = 1024
  , Stdout_wrap = True
  }


functor Make(M : sig

  con u

  val fu : folder u

  constraint [Id,ExitCode,Cmd,Hint] ~ u

  table t : (jobinfo ++ u)

  sequence s

  val completion : (record jobinfo) -> transaction unit

end) = struct


  datatype jobstatus
    = Ready of record jobinfo
    | Running of (channel (record jobinfo)) * (source (record jobinfo))

  val shellCommand = shellCommand
  val defaultIO = defaultIO

  table handles : {Id : int, Channel : channel (record jobinfo)}

  task initialize = fn _ =>
    dml(DELETE FROM handles WHERE Id > 0);
    return {}

  fun callback (jid:int) : transaction page =
    j <- FFI.deref jid;
    ec <- return (FFI.exitcode j);
    er <- return (FFI.errors j);
    cmd <- return (FFI.cmd j);
    dml(UPDATE {{M.t}} SET ExitCode={[Some ec]},Hint={[er]} WHERE Id={[jid]});
    ji <- return {
        Id = jid
      , ExitCode = Some (FFI.exitcode j)
      , Cmd = cmd
      , Hint = er};

    n <- query1 (SELECT * FROM handles WHERE handles.Id = {[jid]}) (fn r s =>
      debug ("Job #" ^ show ji.Id ^ " notifying client " ^ show r.Id);
      send r.Channel ji ;
      return (s+1)) 0;

    debug ("Job #" ^ show ji.Id ^ " notifyed " ^ show n ^ " clients");

    dml (DELETE FROM handles WHERE Id = {[jid]});

    M.completion ji;

    return <xml/>

  fun create
      (ja:record jobargs)
      (injs : record (map sql_injectable M.u))
      (fs : record M.u)
      : transaction FFI.job =

    jid <- nextval M.s;

    j <- create_ jid ja (Some (url (callback jid)));

    FFI.run j;

    dml (insert M.t (

        { Id = sql_inject jid,
          ExitCode = sql_inject None,
          Cmd = sql_inject ja.Cmd,
          Hint = sql_inject ""
        } ++

        (@Top.map2 [sql_injectable] [ident] [sql_exp [] [] []]
          (fn [t] => @sql_inject) M.fu injs fs)
      )
    );
    return j

  fun createSync
      (ja:record jobargs)
      (fs : record M.u)
      : transaction FFI.job =

    jid <- nextval M.s;

    j <- create_ jid ja None;

    FFI.executeSync j;
    FFI.cleanup j;

    return j


  fun monitor (j : FFI.job) =
    jid <- return (FFI.ref j);
    ec <- return (FFI.exitcode j);
    case ec >= 0 of
      |False =>
        c <- channel;
        s <- source ({Id = jid, Cmd = FFI.cmd j,
                      ExitCode = None, Hint = FFI.errors j});
        dml (INSERT INTO handles(Id,Channel) VALUES ({[jid]}, {[c]}));
        return (Running (c,s))

      |True =>
        return (Ready {Id = jid, Cmd = FFI.cmd j,
                      ExitCode = Some ec, Hint = FFI.errors j})

  fun defaultRender (ji : record jobinfo) : xbody =
    <xml>
      ID {[ji.Id]} Cmd {[ji.Cmd]} ExitCode {[ji.ExitCode]} Hint {[ji.Hint]}
    </xml>

  fun monitorX (render : record jobinfo -> xbody) (j : FFI.job) : transaction xbody =
    js <- monitor j;
    case js of
      |Ready j => return (render j)
      |Running (c,ss) =>
        return <xml>
          <active code={spawn (v <- recv c; set ss v); return <xml/>}/>
          <dyn signal={v <- signal ss; return (render v)}/>
          </xml>

end



functor MakeSync(M : sig

  sequence s

end) = struct

  val shellCommand = shellCommand
  val defaultIO = defaultIO

  fun createSync
      (ja:record jobargs)
      : transaction FFI.job =

    jid <- nextval M.s;

    j <- create_ jid ja None;

    FFI.executeSync j;
    FFI.cleanup j;

    return j

end

