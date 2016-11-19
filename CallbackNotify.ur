
con jobrec = Callback.jobrec
con jobinfo = Callback.jobinfo

type job = record jobrec

datatype jobstatus = Ready of (record jobinfo) | Running of (channel (record jobinfo)) * (source (record jobinfo))

table handles : {JobRef : int, Channel : channel (record jobinfo)}

type jobref = CallbackFFI.jobref

type jobargs = Callback.jobargs_


signature S = sig

  val nextJobRef : transaction jobref

  type jobref = CallbackFFI.jobref

  val create : jobargs -> transaction jobref

  val shellCommand : string -> jobargs

  val absCommand : string -> list string -> jobargs

  val monitor : jobref -> transaction jobstatus

  val monitorX : jobref -> (record jobinfo -> xbody) -> transaction xbody

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

    val callback = fn (ji:record jobinfo) =>
      query1 (SELECT * FROM handles WHERE handles.JobRef = {[ji.JobRef]}) (fn r s =>
        send r.Channel ji;
        return s) {};
      dml (DELETE FROM handles WHERE JobRef = {[ji.JobRef]});
      return {}

  end)

  type jobref = CallbackFFI.jobref

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
end

structure Default = Make(
  struct
    val gc_depth = 1000
    val stdout_sz = 10*1024
    val stdin_sz = 10*1024
    val callback = (fn _ => return {})
  end)
