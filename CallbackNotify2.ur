
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

  val create : option blob -> transaction jobref

  val monitor : jobref -> transaction xbody

  val abortMore : int -> transaction int

end

functor Make(S :
sig

  val cmd : string

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

  fun create stdin =
    jr <- C.nextjob {};
    (case stdin of
     |None => C.create jr S.cmd (textBlob "")
     |Some stdin => C.create jr S.cmd stdin);
    return jr

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

  val abortMore = C.abortMore
end




