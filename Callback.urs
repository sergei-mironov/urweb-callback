
datatype aval t = Ready of t | Future of (channel t) * (source t)

val getXml : aval xbody -> xbody 

con jobrec = [JobRef = int, ExitCode = option int, Cmd = string, Stdin = string, StdinB = option blob, Stdout = string]

functor Make(S :
sig

  (* Representation of a job *)
  type t

  (* A convertor from jobrecord to the user-defined type t *)
  val f : record jobrec -> transaction t

end) :

sig

  type jobref = CallbackFFI.jobref

  val create : string -> string -> transaction jobref

  val createB : string -> blob -> transaction jobref

  val monitor : jobref -> S.t -> transaction (aval S.t)

  type job = CallbackFFI.job
  val deref : jobref -> transaction job
  val exitcode : job -> int
  val stdout : job -> string

end
