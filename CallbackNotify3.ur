
con jobinfo = Callback.jobinfo

con jobrec = Callback.jobrec

datatype jobstatus t = Ready of (record (jobrec t)) | Running of (channel (record (jobrec t)))

type jobref = CallbackFFI.jobref

type jobargs = Callback.jobargs_


functor Make(S :
sig

  type t

  val ti1 : sql_injectable t

  val tdef : t

  val gc_depth : int

  val stdout_sz : int

  val stdin_sz : int

  val callback : channel ( record (jobrec t) ) -> record (jobrec t) -> transaction unit

end) : sig

  val handles : sql_table [JobRef = int, Channel = channel (record (jobrec S.t))] [Pkey=[JobRef]]

  val nextJobRef : transaction jobref

  type jobref = CallbackFFI.jobref

  val create : jobargs -> transaction jobref

  val shellCommand : string -> jobargs

  val absCommand : string -> list string -> jobargs

  val monitor : jobref -> transaction (jobstatus S.t)

  val monitorX : jobref -> (record (jobrec S.t) -> xbody) -> transaction xbody

  val abortMore : int -> transaction int

end
 =

struct

  table handles : [JobRef = int, Channel = channel (record (jobrec S.t))]
    PRIMARY KEY JobRef

  structure C = Callback.Make (struct

    type t = S.t
    val ti1 = S.ti1
    val tdef = S.tdef

    val gc_depth = S.gc_depth
    val stdout_sz = S.stdout_sz
    val stdin_sz = S.stdin_sz

    val callback = fn (ji:record (jobrec t)) =>
      query1 (SELECT * FROM handles WHERE handles.JobRef = {[ji.JobRef]}) (fn r s =>
        S.callback r.Channel ji;
        return s) {};
      dml (DELETE FROM handles WHERE JobRef = {[ji.JobRef]} OR JobRef < {[ji.JobRef-S.gc_depth]});
      return {}

  end)

  type jobref = CallbackFFI.jobref

  val nextJobRef = C.nextJobRef

  val create = C.create

  val abortMore = C.abortMore

  val shellCommand = C.shellCommand

  val absCommand = C.absCommand

  val jobs = C.jobs

  fun monitor (jr:jobref) : transaction (jobstatus S.t) =
    a <- oneRow1(SELECT * FROM jobs AS J WHERE J.JobRef = {[jr]});
    case a.ExitCode of
      |None =>
        c <- channel;
        dml (INSERT INTO handles(JobRef,Channel) VALUES ({[jr]}, {[c]}));
        return (Running c)
      |Some _ =>
        return (Ready a)

  fun monitorX jr render =
    js <- monitor jr;
    case js of
      |Ready a => return (render a)
      |Running c =>
        sx <- source <xml/>;
        return <xml>
          <dyn signal={x <- signal sx; return x}/>
          <active code={spawn (v <- recv c; set sx (render v)); return <xml/>}/>
          </xml>
end

structure Default = Make(
  struct
    type t = int
    val tdef = 0
    val gc_depth = 1000
    val stdout_sz = 10*1024
    val stdin_sz = 10*1024
    val callback = (fn c x => send c x)
  end)

