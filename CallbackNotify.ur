
con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

type job = record jobrec

datatype jobstatus = Ready of job | Running of (channel job) * (source job)

table handles : {JobRef : int, Channel : channel job}

type jobref = CallbackFFI.jobref

structure C = Callback.Make (struct
  val gc_depth = 100
  val stdout_sz = 1024
  val stdin_sz = 1024

  val callback = fn (ji:job) =>
    query1 (SELECT * FROM handles WHERE handles.JobRef = {[ji.JobRef]}) (fn r s =>
      send r.Channel ji;
      return s) {};
    dml (DELETE FROM handles WHERE JobRef = {[ji.JobRef]});
    return {}
  
end)

val nextJobRef = C.nextJobRef

type jobargs = C.jobargs

val create = C.create

val jobs = Callback.jobs

val abortMore = C.abortMore

val shellCommand = C.shellCommand

fun monitor jr = 
  r <- C.get jr;
  case r.ExitCode of
    |None =>
      c <- channel;
      s <- source r;
      dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
      return (Running (c,s))
    |Some (ec:int) =>
      return (Ready r)

fun monitorX jr render =
  js <- monitor jr;
  case js of
    |Ready j => return (render j)
    |Running (c,ss) =>
      return <xml>
        <dyn signal={v <- signal ss; return (render v)}/>
        <active code={spawn (v <- recv c; set ss v); return <xml/>}/>
        </xml>

