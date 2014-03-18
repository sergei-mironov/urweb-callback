
con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

datatype jobval t = Ready of t | Running of (channel t) * (source t)

type jobresult = jobval (record jobrec)

table handles : {JobRef : int, Channel : channel (record jobrec)}

type jobref = CallbackFFI.jobref

structure C = Callback.Make (struct
  val gc_depth = 100
  val stdout_sz = 1024

  val callback = fn (ji:(record jobrec)) => 
    query1 (SELECT * FROM handles WHERE handles.JobRef = {[ji.JobRef]}) (fn r s =>
      send r.Channel ji;
      return s) {};
    dml (DELETE FROM handles WHERE JobRef = {[ji.JobRef]});
    return {}
  
end)

val nextjob = C.nextjob

val create = C.create

val jobs = Callback.jobs

fun monitor (jr:jobref) = 
  r <- oneRow (SELECT * FROM jobs WHERE jobs.JobRef = {[jr]});
  case r.Jobs.ExitCode of
    |None =>
      c <- channel;
      s <- source (r.Jobs);
      dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
      return (Running (c,s))
    |Some (ec:int) =>
      return (Ready r.Jobs)


