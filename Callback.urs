
type job
type jobref = Basis.int

val create : string -> string -> int -> transaction jobref
val run: jobref -> url -> transaction unit
val cleanup: jobref -> transaction unit

val find : jobref -> job
val ref : job -> jobref

val pid : jobref -> int
val exitcode : jobref -> int
val stdout : jobref -> string
val errors : jobref -> string
