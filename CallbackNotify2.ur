
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

  type jobargs = Callback.jobargs_

  val create : jobargs -> transaction jobref

  val createDefault : option blob -> transaction jobref


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

  type jobargs = Callback.jobargs_

  structure C = Callback.Make(struct
    val gc_depth = 100
    val stdout_sz = 1024
    val stdin_sz = 1024

    val callback = fn (j:job) =>
      b <- S.render j;
      query1 (SELECT * FROM handles WHERE handles.JobRef = {[j.JobRef]}) (fn r s =>
        send r.Channel b;
        return s) {};
      dml (DELETE FROM handles WHERE JobRef = {[j.JobRef]});
      return {}
  end)

  val create = C.create

  fun createDefault b =
    c <- (case b of
      |Some b => return (Callback.Chunk (b,Some Callback.EOF))
      |None => return (Callback.Chunk (textBlob "",Some Callback.EOF)));
    C.create {Cmd = S.cmd, Stdin = c, Args = []}

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




