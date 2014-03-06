con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
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


sequence jobrefs

table jobs : $jobrec
  PRIMARY KEY JobRef

functor Make(S :
sig
  type t
  val f : record jobrec -> transaction t

  val depth : int

  val stdout_sz : int

end) :

sig

  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> blob -> transaction unit

  val monitor : jobref -> S.t -> transaction (aval S.t)

  val lastLine : string -> string

  val get : jobref -> transaction (record jobrec)

  val runNow : jobref -> string -> blob -> transaction (record jobrec)

end =

struct

  type jobref = CallbackFFI.jobref

  fun nextjob {} = nextval jobrefs

  table handles : {JobRef : int, Channel : channel S.t}

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
    dml (DELETE FROM jobs WHERE JobRef < {[jr-S.depth]} AND ExitCode <> NULL);
    CallbackFFI.cleanup j;
    return <xml/>

  fun create (jr:jobref) (cmd:string) (inp:blob) : transaction unit =
    j <- CallbackFFI.create cmd S.stdout_sz jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, ""));
    CallbackFFI.run j inp (Some (url (callback jr)));
    return {}

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

