
con jobrec = [JobRef = int, ExitCode = option int, Cmd = string, Stdin = string, Stdout = string]

functor Make(S :
sig
  type t
  val f : record jobrec -> transaction t
end) :

sig

  type jobref = CallbackFFI.jobref

  val create : string -> string -> transaction jobref

  val monitor : jobref -> S.t -> transaction (Cb.aval S.t)

end
