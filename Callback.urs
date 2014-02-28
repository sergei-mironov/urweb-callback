
datatype aval t = Ready of t | Future of (channel t) * (source t)

val getXml : aval xbody -> xbody 

con jobrec = [JobRef = int, ExitCode = option int, Cmd = string, Stdout = string]

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

  val exitcode : jobref -> transaction (option int)

  val stdout : jobref -> transaction string

  val lastLineOfStdout : jobref -> transaction string

end
