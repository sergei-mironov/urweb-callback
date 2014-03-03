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

  val exitcode : jobref -> transaction (option int)

  val stdout : jobref -> transaction string

  val lastLineOfStdout : jobref -> transaction string

  val get : jobref -> transaction (record jobrec)

  val runNowB : string -> blob -> transaction (record jobrec)

  val runNow : string -> string -> transaction (record jobrec)

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

  fun createB (cmd:string) (inp:blob) : transaction jobref =
    jr <- nextval jobrefs;
    j <- CallbackFFI.create cmd 1024 jr;
    dml(INSERT INTO jobs(JobRef,ExitCode,Cmd,Stdout) VALUES ({[jr]}, {[None]}, {[cmd]}, ""));
    CallbackFFI.run j inp (url (callback jr));
    return jr

  fun create (cmd:string) (inp:string) : transaction jobref =
    createB cmd (textBlob inp)

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

  fun exitcode jr =
    mj <- CallbackFFI.tryDeref jr;
    case mj of
      | Some j =>
          e <- return (CallbackFFI.exitcode j);
          if e < 0 then
            return None
          else
            return (Some e)
      | None =>
         r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
         return r.Jobs.ExitCode

  fun stdout jr =
    mj <- CallbackFFI.tryDeref jr;
    case mj of
      | Some j =>
          return (CallbackFFI.stdout j)
      | None =>
          r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
          return r.Jobs.Stdout

  fun lastLineOfStdout jr =
    s <- stdout jr;
    return (CallbackFFI.lastLine s)

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

  fun runNowB cmd stdin =
    jr <- nextval jobrefs;
    j <- CallbackFFI.runNow cmd 1024 stdin jr;
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
    
  fun runNow cmd stdin =
    runNowB cmd (textBlob stdin)

end

