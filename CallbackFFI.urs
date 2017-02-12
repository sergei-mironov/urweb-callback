
type job
type jobref = Basis.int

val initialize : int -> transaction unit

val create : string -> bool -> int -> int -> jobref -> transaction job

val setCompletionCB : job -> option url -> transaction unit
val setNotifyCB : job -> option url -> transaction unit
val pushStdin : job -> blob -> transaction unit
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
val stdout : job -> blob
val stderr : job -> blob
val cmd : job -> string
val errors : job -> string

val executeSync : job -> transaction unit

(* re-run the handler *)
val forceBoundedRetry : string -> transaction unit


val lastLines : int -> blob -> string
val blobLines : blob -> string
