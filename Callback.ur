
con jobrec =
  [
    (* Job reference which may be passed to clients *)
    JobRef = int
    (* Exit code of the job process *)
  , ExitCode = option int
    (* Command line of the job *)
  , Cmd = string
    (* Stdout of the job (at least stdout_sz bytes) *)
  , Stdout = string
  , ErrRep = string
  ]

sequence jobrefs

table jobs : $jobrec
  PRIMARY KEY JobRef

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

fun shellCommand_ s =
  {Cmd = "/bin/sh", Stdin = Chunk (textBlob "", Some EOF), Args = "-c" :: s :: [] }


signature S = sig

  type jobref = CallbackFFI.jobref

  type jobargs = jobargs_

  val nextJobRef : transaction jobref

  val shellCommand : string -> jobargs

  val mkBuffer : string -> buffer

  val create : jobargs -> transaction jobref

  val createWithRef : jobref -> jobargs -> transaction unit

  val createSync : jobargs -> transaction (record jobrec)


  val feed : jobref -> buffer -> transaction unit

  val get : jobref -> transaction (record jobrec)

  val lastLine : string -> string

  val abortMore : int -> transaction int
end


functor Make(S :
sig

  val gc_depth : int

  val stdout_sz : int

  val stdin_sz : int

  val callback : (record jobrec) -> transaction unit

end) : S =

struct

  type jobref = CallbackFFI.jobref

  type jobargs = jobargs_

  val nextJobRef = nextval jobrefs

  val shellCommand = shellCommand_

  val mkBuffer = mkBuffer_

  fun runtimeJobRec j =
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
      Stdout=(CallbackFFI.stdout j),
      ErrRep=(CallbackFFI.errors j)}

  fun callback (jr:jobref) : transaction page =
    j <- CallbackFFI.deref jr;
    ec <- (return (CallbackFFI.exitcode j));
    so <- (return (CallbackFFI.stdout j));
    er <- (return (CallbackFFI.errors j));
    dml(UPDATE jobs SET ExitCode = {[Some ec]}, Stdout = {[so]}, ErrRep = {[er]} WHERE JobRef = {[jr]});
    mji <- oneOrNoRows (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    case mji of
      |None =>
        CallbackFFI.forceBoundedRetry ("Force bounded retry for job #" ^ (show jr));
        return <xml/>
      |Some ji =>
        dml (DELETE FROM jobs WHERE JobRef < {[jr-S.gc_depth]} AND NOT {eqNullable' (SQL ExitCode) None});
        CallbackFFI.cleanup j;
        S.callback ji.Jobs;
        return <xml/>

  fun feed_ j b =
    case b of
     |Chunk (b,Some EOF) =>
        CallbackFFI.pushStdin j b S.stdin_sz;
        CallbackFFI.pushStdinEOF j
     |Chunk (b,None) =>
        CallbackFFI.pushStdin j b S.stdin_sz

  fun createWithRef (jr:jobref) (ja:jobargs) : transaction unit =
    j <- CallbackFFI.create ja.Cmd S.stdout_sz jr;
    mapM_ (CallbackFFI.pushArg j) ja.Args;
    CallbackFFI.setCompletionCB j (Some (url (callback jr)));
    feed_ j ja.Stdin;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout,ErrRep) VALUES ({[jr]}, {[None]}, {[CallbackFFI.cmd j]}, "", ""));
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
      CallbackFFI.pushStdin j b S.stdin_sz;
      CallbackFFI.pushStdinEOF j;
      CallbackFFI.executeSync j;
      jrec <- runtimeJobRec j;
      CallbackFFI.cleanup j;
      return jrec
    end

  val feed jr b : transaction unit =
    j <- CallbackFFI.deref jr;
    feed_ j b

  val lastLine = CallbackFFI.lastLine

  fun get jr =
    mj <- CallbackFFI.tryDeref jr;
    case mj of
      |Some j =>
        runtimeJobRec j
      |None =>
        r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
        return r.Jobs

  val abortMore l =
    CallbackFFI.limitActive l;
    n <- CallbackFFI.nactive;
    return n

end

structure Default = Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 1024
    val stdin_sz = 1024
    val callback = fn _ => return {}
  end)

