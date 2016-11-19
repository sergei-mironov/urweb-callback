(* Under development *)

con jobinfo = Callback.jobinfo
con jobrec = Callback.jobrec

signature S = sig

  type jobref = CallbackFFI.jobref

  type jobargs = Callback.jobargs_

  val create : jobargs  -> transaction jobref

  val createDefault : option blob -> transaction jobref

  val monitor : jobref -> transaction xbody

  val abortMore : int -> transaction int

end

functor Make(S :
sig

  val cmd : string

  val render : (record jobinfo) -> transaction xbody

end) : S
