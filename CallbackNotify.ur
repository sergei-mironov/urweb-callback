
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  , Stderr = string
  , ErrRep = string
  ]

type job = record jobrec

datatype jobstatus = Ready of job | Running of (channel job) * (source job)

table handles : {JobRef : int, Channel : channel job}

type jobref = CallbackFFI.jobref

type jobargs = Callback.jobargs_


fun portJob (j: record Callback.jobrec): record jobrec =
  (j -- #Stderr -- #Stdout ++
    {Stdout = Callback.blobLines j.Stdout, Stderr = Callback.blobLines j.Stderr})

signature S = sig

  val nextJobRef : transaction jobref

  val create : jobargs -> transaction jobref

  val shellCommand : string -> jobargs

  val absCommand : string -> list string -> jobargs

  val monitor : jobref -> transaction jobstatus

  val monitorX : jobref -> (job -> xbody) -> transaction xbody

  (*
   * Aborts the handler if the number of jobs exceeds the limit.
   * Returns the actual number of job objects in memory.
   *)
  val abortMore : int -> transaction int

end

functor Make(S :
sig

  val gc_depth : int

  val stdout_sz : int

  val stdin_sz : int

end) : S =

struct

  structure C = Callback.Make (struct
    val gc_depth = S.gc_depth
    val stdout_sz = S.stdout_sz
    val stdin_sz = S.stdin_sz

    val callback = fn (ji:record Callback.jobrec) =>
      query1 (SELECT * FROM handles WHERE handles.JobRef = {[ji.JobRef]}) (fn r s =>
        debug ("[CB] Got callback from job #" ^ (show ji.JobRef));
        send r.Channel (portJob ji) ;
        return s) {};
      dml (DELETE FROM handles WHERE JobRef = {[ji.JobRef]});
      return {}

  end)

  val nextJobRef = C.nextJobRef

  val create = C.create

  val abortMore = C.abortMore

  val shellCommand = C.shellCommand

  val absCommand = C.absCommand

  fun monitor jr =
    r <- C.get jr;
    case r.ExitCode of
      |None =>
        c <- channel;
        s <- source (portJob r);
        dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
        return (Running (c,s))
      |Some (ec:int) =>
        return (Ready (portJob r))

  fun monitorX jr render =
    js <- monitor jr;
    case js of
      |Ready j => return (render j)
      |Running (c,ss) =>
        return <xml>
          <dyn signal={v <- signal ss; return (render v)}/>
          <active code={spawn (v <- recv c; set ss v); return <xml/>}/>
          </xml>
end

structure Default = Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 10*1024
    val stdin_sz = 10*1024
  end)
