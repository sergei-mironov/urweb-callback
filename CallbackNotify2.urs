
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  ]

signature S = sig

  type jobref = CallbackFFI.jobref

  val create : option blob -> transaction jobref

  val monitor : jobref -> transaction xbody

  val abortMore : int -> transaction int

end

functor Make(S :
sig

  val cmd : string

  val render : (record jobrec) -> transaction xbody

end) : S
