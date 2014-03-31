
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  ]

type job = record jobrec

datatype jobstatus = Ready of xbody | Running of (channel xbody) * (source xbody)

table handles : {JobRef : int, Channel : channel xbody}

type jobref = CallbackFFI.jobref

signature S = sig

  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> option blob -> transaction unit

  val monitor : jobref -> transaction xbody

end

functor Make(S :
sig

  val render : (record jobrec) -> transaction xbody

end) : S =

struct

  type jobref = CallbackFFI.jobref

  structure C = Callback.Make(struct
    val gc_depth = 100
    val stdout_sz = 1024

    val callback = fn (j:job) =>
      b <- S.render j;
      query1 (SELECT * FROM handles WHERE handles.JobRef = {[j.JobRef]}) (fn r s =>
        send r.Channel b;
        return s) {};
      dml (DELETE FROM handles WHERE JobRef = {[j.JobRef]});
      return {}
  end)

  val nextjob = C.nextjob

  fun create jr cmd stdin =
    case stdin of
      |None => C.create jr cmd (textBlob "")
      |Some stdin => C.create jr cmd stdin

  fun monitor_s (jr:jobref) : transaction jobstatus =
    r <- C.get jr;
    b <- S.render r;
    case r.ExitCode of
      |None =>
        c <- channel;
        s <- source b;
        dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
        return (Running (c,s))
      |Some (ec:int) =>
        return (Ready b)

  fun monitor jr = 
    js <- monitor_s jr;
    case js of
      |Ready b => return b
      |Running (c,ss) =>
        return <xml>
          <dyn signal={v <- signal ss; return v}/>
          <active code={spawn (v <- recv c; set ss v); return <xml/>}/>
          </xml>

end




