
con jobinfo = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , ErrRep = string
  ]

con jobrec t = jobinfo ++ [Payload = t]

sequence jobrefs

task initialize = fn _ =>
  CallbackFFI.initialize 4;
  return {}

fun mapM_ a b = i <- List.mapM a b; return {}

datatype eof = EOF

datatype buffer = Chunk of blob * (option eof)

fun mkBuffer_ s = Chunk (textBlob s, Some EOF)

type jobargs_ = {
    Cmd : string
  , Stdin : buffer
  , Args : list string
  }

val lastLines = CallbackFFI.lastLines

val blobLines = CallbackFFI.blobLines

fun checkString (f:string -> bool) (s:string) : transaction string =
  return (case f s of
    |False => error <xml>checkString failed on {[s]}</xml>
    |True => s)

fun shellCommand_ s =
  {Cmd = "/bin/sh", Stdin = Chunk (textBlob "", Some EOF), Args = "-c" :: s :: [] }

fun absCommand_ cmd args =
  {Cmd = cmd, Stdin = Chunk (textBlob "", Some EOF), Args = args}


functor Make(S : sig

  type t

  val ti1 : sql_injectable t

  val tdef : t

  val gc_depth : int

  val stdout_sz : int

  val stdin_sz : int

  val callback : (record (jobrec t)) -> transaction unit

end) : sig

  val jobs : sql_table (jobrec S.t) [Pkey=[JobRef]]

  type jobref = CallbackFFI.jobref

  type jobargs = jobargs_

  val nextJobRef : transaction jobref

  val shellCommand : string -> jobargs

  val absCommand : string -> (list string) -> jobargs

  val mkBuffer : string -> buffer

  val create : jobargs -> transaction jobref

  val createWithRef : jobref -> jobargs -> transaction unit

  val createSync : jobargs -> transaction jobref

  val feed : jobref -> buffer -> transaction unit

  val abortMore : int -> transaction int

end

 =

struct

  type t = S.t
  val ti1 = S.ti1

  table jobs : (jobrec S.t)
    PRIMARY KEY JobRef

  type jobref = CallbackFFI.jobref

  type jobargs = jobargs_

  val nextJobRef = nextval jobrefs

  val shellCommand = shellCommand_

  val absCommand = absCommand_

  val mkBuffer = mkBuffer_

  fun runtimeJobRec j : transaction (record jobinfo) =
    e <- (let val e = CallbackFFI.exitcode j in
            if e < 0 then
              return None
            else
              return (Some e)
          end);
    return {
      JobRef=(CallbackFFI.ref j),
      ExitCode=e,
      Cmd=(CallbackFFI.cmd j),
      ErrRep=(CallbackFFI.errors j)}

  fun callback (jr:jobref) : transaction page =
    j <- CallbackFFI.deref jr;
    ec <- (return (CallbackFFI.exitcode j));
    er <- (return (CallbackFFI.errors j));
    dml(UPDATE jobs SET ExitCode = {[Some ec]}, ErrRep = {[er]} WHERE JobRef = {[jr]});
    mji <- oneOrNoRows (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    case mji of
      |None =>
        CallbackFFI.forceBoundedRetry ("Force bounded retry for job #" ^ (show jr));
        return <xml/>
      |Some ji =>
        S.callback ji.Jobs;
        dml (DELETE FROM jobs WHERE JobRef < {[jr-S.gc_depth]} AND NOT {eqNullable' (SQL ExitCode) None});
        CallbackFFI.cleanup j;
        return <xml/>

  fun feed_ j b =
    case b of
     |Chunk (b,Some EOF) =>
        CallbackFFI.pushStdin j b S.stdin_sz;
        CallbackFFI.pushStdinEOF j
     |Chunk (b,None) =>
        CallbackFFI.pushStdin j b S.stdin_sz

  fun createWithRef (jr:jobref) (ja:jobargs) : transaction unit =
    debug ("BUFSZ:"^(show S.stdout_sz));
    j <- CallbackFFI.create ja.Cmd S.stdout_sz jr;
    mapM_ (CallbackFFI.pushArg j) ja.Args;
    CallbackFFI.setCompletionCB j (Some (url (callback jr)));
    feed_ j ja.Stdin;
    nullb <- return (textBlob "");
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,ErrRep,Payload)
        VALUES ({[jr]}, {[None]}, {[CallbackFFI.cmd j]}, "", {[S.tdef]}));
    CallbackFFI.run j;
    return {}

  fun create (ja:jobargs) : transaction jobref =
    jr <- nextJobRef;
    createWithRef jr ja;
    return jr

  fun createSync ja =
    let
      val Chunk (b,_) = ja.Stdin
    in
      jr <- nextJobRef;
      j <- CallbackFFI.create ja.Cmd S.stdout_sz jr;
      mapM_ (CallbackFFI.pushArg j) ja.Args;
      CallbackFFI.pushStdin j b (blobSize b);
      CallbackFFI.pushStdinEOF j;
      CallbackFFI.executeSync j;
      CallbackFFI.cleanup j;
      return jr
    end

  val feed jr b : transaction unit =
    j <- CallbackFFI.deref jr;
    feed_ j b

  (* fun get jr = *)
  (*   mj <- CallbackFFI.tryDeref jr; *)
  (*   case mj of *)
  (*     |Some j => *)
  (*       runtimeJobRec j *)
  (*     |None => *)
  (*       r <- oneRow (SELECT * FROM jobs AS J WHERE J.JobRef = {[jr]}); *)
  (*       return r.J *)

  fun abortMore l =
    CallbackFFI.limitActive l;
    n <- CallbackFFI.nactive;
    return n

end

structure Default = Make(
  struct
    type t = int
    val tdef = 0
    val gc_depth = 1000
    val stdout_sz = 10*1024
    val stdin_sz = 10*1024
    val callback = fn _ => return {}
  end)

