
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  ]

signature S = sig

  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> option blob -> transaction unit

  val monitor : jobref -> transaction xbody

end

functor Make(S :
sig

  val render : (record jobrec) -> transaction xbody

end) : S
