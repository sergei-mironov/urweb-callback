
type job
type jobref = Basis.int

val initialize : int -> transaction unit

val create : string -> int -> jobref -> transaction job

val setCompletionCB : job -> option url -> transaction unit
val setNotifyCB : job -> option url -> transaction unit
val pushStdin : job -> blob -> int -> transaction unit
val pushStdinEOF : job -> transaction unit
val pushArg : job -> string -> transaction unit
val run: job -> transaction unit
val cleanup: job -> transaction unit

val nactive : transaction int
val limitActive : int -> transaction unit

val tryDeref : jobref -> transaction (option job)
val deref : jobref -> transaction job
val ref : job -> jobref

val pid : job -> int
val exitcode : job -> int
val stdout : job -> string
val stderr : job -> string
val cmd : job -> string
val errors : job -> string


val lastLines : int -> string -> string


val executeSync : job -> transaction unit

(* re-run the handler *)
val forceBoundedRetry : string -> transaction unit

