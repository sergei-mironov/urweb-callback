
type job = Basis.int

val create : string -> string -> int -> transaction job
val run: job -> url -> transaction unit
val cleanup: job -> transaction unit

val pid : job -> int
val exitcode : job -> int
val stdout : job -> string
val errors : job -> string
