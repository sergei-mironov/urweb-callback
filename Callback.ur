con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

sequence jobrefs

table jobs : $jobrec
  PRIMARY KEY JobRef

signature S = sig
  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> blob -> transaction unit

  val get : jobref -> transaction (record jobrec)

  val runNow : jobref -> string -> blob -> transaction (record jobrec)

  val lastLine : string -> string
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
        CallbackFFI.forceBoundedRetry ("Force bounded retry for job " ^ (show jr));
        return <xml/>
      |Some ji =>
        dml (DELETE FROM jobs WHERE JobRef < {[jr-S.gc_depth]} AND ExitCode <> NULL);
        CallbackFFI.cleanup j;
        S.callback ji.Jobs;
        return <xml/>

  fun create (jr:jobref) (cmd:string) (inp:blob) : transaction unit =
    j <- CallbackFFI.create cmd S.stdout_sz jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, ""));
    debug ("job create " ^ (show jr));
    CallbackFFI.run j inp (Some (url (callback jr)));
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


end

structure Default = Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 1024
    val callback = fn _ => return {}
  end)

