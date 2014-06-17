con jobrec = Callback.jobrec

type job = record jobrec

datatype jobstatus = Ready of job | Running of (channel job) * (source job)

type jobref = CallbackFFI.jobref

val nextJobRef : transaction jobref

type jobargs = Callback.jobargs_

val create : jobargs -> transaction jobref

val shellCommand : string -> jobargs

val monitor : jobref -> transaction jobstatus

val monitorX : jobref -> (job -> xbody) -> transaction xbody

(*
 * Aborts the handler if the number of jobs exceeds the limit.
 * Returns the actual number of job objects in memory.
 *)
val abortMore : int -> transaction int
