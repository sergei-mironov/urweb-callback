con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

type job = record jobrec

datatype jobstatus = Ready of job | Running of (channel job) * (source job)

type jobref = CallbackFFI.jobref

val nextjob : unit -> transaction jobref

val create : jobref -> string -> blob -> transaction unit

val monitor : jobref -> transaction jobstatus

val monitorX : jobref -> (job -> xbody) -> transaction xbody
