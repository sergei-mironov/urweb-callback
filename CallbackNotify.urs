con jobrec = [
  JobRef = int,
  ExitCode = option int,
  Cmd = string,
  Stdout = string]

datatype jobval t = Ready of t | Running of (channel t) * (source t)

type job = record jobrec

type jobresult = jobval job

type jobref = CallbackFFI.jobref

val nextjob : unit -> transaction jobref

val create : jobref -> string -> blob -> transaction unit

val monitor : jobref -> transaction jobresult
