con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdin = string,
  StdinB = option blob,
  Stdout = string]

datatype aval t = Ready of t | Future of (channel t) * (source t)

fun getXml a =
  case a of
      Ready p => p
    | Future (c,s) =>
        <xml>
          <dyn signal={signal s}/>
          <active code={spawn (v <- recv c; set s v); return <xml/>}/>
        </xml>

functor Make(S :
sig
  type t
  val f : record jobrec -> transaction t
end) :

sig

  type jobref = CallbackFFI.jobref

  val create : string -> string -> transaction jobref

  val createB : string -> blob -> transaction jobref

  val monitor : jobref -> S.t -> transaction (aval S.t)

  type job = CallbackFFI.job

  val deref : jobref -> transaction job
  val exitcode : job -> int
  val stdout : job -> string

  val lastLineOfStdout : job -> string

end =

struct

  type jobref = CallbackFFI.jobref

  table jobs : $jobrec
    PRIMARY KEY JobRef

  table handles : {JobRef : int, Channel : channel S.t}

  sequence jobrefs

  fun callback (jr:jobref) : transaction page =
    j <- CallbackFFI.deref jr;
    ec <- (return (CallbackFFI.exitcode j));
    so <- (return (CallbackFFI.stdout j));
    dml(UPDATE jobs SET ExitCode = {[Some ec]}, Stdout = {[so]} WHERE JobRef = {[jr]});
    ji <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    query1 (SELECT * FROM handles WHERE handles.JobRef = {[jr]}) (fn r s =>
      t <- S.f ji.Jobs;
      send r.Channel t;
      return s) {};
    dml (DELETE FROM handles WHERE JobRef = {[jr]});
    CallbackFFI.cleanup j;
    return <xml/>

  fun create (cmd:string) (inp:string) : transaction jobref =
    jr <- nextval jobrefs;
    j <- CallbackFFI.create cmd inp 256 jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdin,StdinB,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, {[inp]}, NULL, ""));
    CallbackFFI.run j (url (callback jr));
    return jr

  fun createB (cmd:string) (inp:blob) : transaction jobref =
    jr <- nextval jobrefs;
    j <- CallbackFFI.createB cmd inp 256 jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdin,StdinB,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, "", {[Some inp]}, ""));
    CallbackFFI.run j (url (callback jr));
    return jr

  fun monitor (jr:jobref) (d:S.t) =
    r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    case r.Jobs.ExitCode of
      | None =>
          c <- channel;
          s <- source d;
          dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
          return (Future (c,s))
      | Some (ec:int) =>
          t <- S.f r.Jobs;
          return (Ready t)

  type job = CallbackFFI.job
  val deref = CallbackFFI.deref
  val stdout = CallbackFFI.stdout
  val exitcode = CallbackFFI.exitcode
  val lastLineOfStdout = CallbackFFI.lastLineOfStdout

(*
  fun monitor (jr:jobref) (d:S.t) =
    r <- oneOrNoRows (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
    case r of
        None => return (Ready d)
      | Some r =>
          case r.Jobs.ExitCode of
              None =>
                c <- channel;
                s <- source d;
                dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
                return (Future (c,s))
            | Some (ec:int) =>
                t <- S.f r.Jobs;
                return (Ready t)
*)

end

