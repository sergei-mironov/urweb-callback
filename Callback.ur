
type jobref = CallbackFFI.jobref

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

functor Make(M : sig

  con u

  val fu : folder u

  constraint [Id,ExitCode,Cmd,Hint] ~ u

  table t : (jobinfo ++ u)

  sequence s

  val completion : (record jobinfo) -> transaction unit

end) = struct

  structure FFI = CallbackFFI

  fun shellCommand (s:string) : jobargs =
    { Cmd = "/bin/sh"
    , Args = "-c" :: s :: []
    }

  fun callback (jid:int) : transaction page =
    j <- FFI.deref jid;
    ec <- return (FFI.exitcode j);
    er <- return (FFI.errors j);
    dml(UPDATE {{M.t}} SET ExitCode={[Some ec]},Hint={[er]} WHERE Id={[jid]});
    M.completion {
        Id = jid
      , ExitCode = Some (FFI.exitcode j)
      , Cmd = FFI.cmd j
      , Hint = er};
    return <xml/>

  fun create
      (ja:record jobargs)
      (injs : record (map sql_injectable M.u))
      (fs : record M.u)
      : transaction FFI.job =

    jid <- nextval M.s;

    j <- FFI.create ja.Cmd ja.Stdout_wrap ja.Stdin_sz ja.Stdout_sz jid;
    _ <- List.mapM (FFI.pushArg j) ja.Args;
    FFI.setCompletionCB j (Some (url (callback jid)));
    (case ja.Stdin of
     |Chunk (b,True) =>
       FFI.pushStdin j b;
       FFI.pushStdinEOF j
     |Chunk (b,False) =>
       FFI.pushStdin j b);
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


  datatype jobstatus
    = Ready of jobinfo
    | Running of (channel jobinfo) * (source jobinfo)

  table handles : {Id : int, Channel : channel jobinfo}

  fun monitor (j : FFI.job) =

    jid <- return FFI.ref j;
    case FFI.exitcode j of
      |None =>
        c <- channel;
        s <- source ({Id = jid, Cmd = FFI.cmd j,
                      ExitCode = None, Hint = FFI.errors j});
        dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jid]}, {[c]}));
        return (Running (c,s))

      |Some (ec:int) =>
        return (Ready {Id = jid, Cmd = FFI.cmd j,
                      ExitCode = Some ec, Hint = FFI.errors j})

  fun monitorX (j : FFI.job) render =
    js <- monitor j;
    case js of
      |Ready j => return (render j)
      |Running (c,ss) =>
        return <xml>
          <dyn signal={v <- signal ss; return (render v)}/>
          <active code={spawn (v <- recv c; set ss v); return <xml/>}/>
          </xml>

end


