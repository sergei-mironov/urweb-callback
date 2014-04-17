con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

sequence jobrefs

table jobs : $jobrec
  PRIMARY KEY JobRef

type jobargs = {
    Cmd : string
  , Stdin : option blob
  , Args : list string
  }

task initialize = fn _ =>
  CallbackFFI.initialize 4;
  return {}

fun mapM_ a b = i <- List.mapM a b; return {}

signature S = sig
  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> blob -> transaction unit

  val create2 : jobref -> jobargs -> transaction unit

  val get : jobref -> transaction (record jobrec)

  val runNow : jobref -> string -> blob -> transaction (record jobrec)

  val lastLine : string -> string

  val abortMore : int -> transaction int
end


functor Make(S :
sig

  val gc_depth : int

  val stdout_sz : int

  val callback : (record jobrec) -> transaction unit

end) : S =

struct

  type jobref = CallbackFFI.jobref

  fun nextjob {} = nextval jobrefs

  fun callback (jr:jobref) : transaction page =
    j <- CallbackFFI.deref jr;
    ec <- (return (CallbackFFI.exitcode j));
    so <- (return (CallbackFFI.stdout j));
    dml(UPDATE jobs SET ExitCode = {[Some ec]}, Stdout = {[so]} WHERE JobRef = {[jr]});
    mji <- oneOrNoRows (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    case mji of
      |None =>
        CallbackFFI.forceBoundedRetry ("Force bounded retry for job #" ^ (show jr));
        return <xml/>
      |Some ji =>
        dml (DELETE FROM jobs WHERE JobRef < {[jr-S.gc_depth]} AND ExitCode <> NULL);
        CallbackFFI.cleanup j;
        S.callback ji.Jobs;
        return <xml/>

  fun create (jr:jobref) (cmd:string) (inp:blob) : transaction unit =
    j <- CallbackFFI.create cmd S.stdout_sz jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, ""));
    CallbackFFI.setCompletionCB j (Some (url (callback jr)));
    CallbackFFI.pushStdin j inp (blobSize inp);
    CallbackFFI.pushStdinEOF j;
    CallbackFFI.run j;
    return {}

  fun create2 jr (ja:jobargs) : transaction unit =
    j <- CallbackFFI.create ja.Cmd S.stdout_sz jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[None]}, {[ja.Cmd]}, ""));
    debug ("job create2 " ^ (show jr));
    CallbackFFI.setCompletionCB j (Some (url (callback jr)));
    (case ja.Stdin of
     |Some i => CallbackFFI.pushStdin j i (blobSize i)
     |None => return {});
    mapM_ (CallbackFFI.pushArg j) ja.Args;
    CallbackFFI.run j;
    return {}

  val lastLine = CallbackFFI.lastLine

  fun get jr =
    mj <- CallbackFFI.tryDeref jr;
    case mj of
      |Some j =>
        e <- (let val e = CallbackFFI.exitcode j in
                if e < 0 then
                  return None
                else
                  return (Some e)
              end);
        return {JobRef=jr, ExitCode=e, Cmd=(CallbackFFI.cmd j), Stdout=(CallbackFFI.stdout j)}
      |None =>
        r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
        return r.Jobs

  fun runNow jr cmd stdin =
    j <- CallbackFFI.runNow cmd S.stdout_sz stdin jr;
    e <- (let val e = CallbackFFI.exitcode j in
            if e < 0 then
              return None
            else
              return (Some e)
          end);
    so <- return (CallbackFFI.stdout j);
    (* Don't waste the diskspace by inserting anything into the databse
      dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[e]}, {[cmd]}, {[so]})); *)
    CallbackFFI.cleanup j;
    return {JobRef=jr, ExitCode=e, Cmd=(CallbackFFI.cmd j), Stdout=(CallbackFFI.stdout j)}

  val abortMore limit =
    n <- CallbackFFI.nactive {};
    case limit of
      |0 => return n
      |_ =>
        (case n > limit of
          |False => return n
          |True => error (<xml>Active jobs limit exceeded: active {[n]} limit {[limit]}</xml>))

end

structure Default = Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 1024
    val callback = fn _ => return {}
  end)

