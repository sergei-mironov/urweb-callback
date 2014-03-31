
type job
type jobref = Basis.int

val create : string -> int -> jobref -> transaction job

val setCompletionCB : job -> option url -> transaction unit
val setNotifyCB : job -> option url -> transaction unit
val pushStdin : job -> blob -> int -> transaction unit
val pushStdinEOF : job -> transaction unit
val run: job -> transaction unit
val cleanup: job -> transaction unit

val nactive : unit -> transaction int

val tryDeref : jobref -> transaction (option job)
val deref : jobref -> transaction job
val ref : job -> jobref

val pid : job -> int
val exitcode : job -> int
val stdout : job -> string
val cmd : job -> string
val errors : job -> string


val lastLine : string -> string

val runNow : string -> int -> blob -> jobref -> transaction job

(* re-run the handler *)
val forceBoundedRetry : string -> transaction unit

