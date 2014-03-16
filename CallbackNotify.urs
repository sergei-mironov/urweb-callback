
functor Make(S :
sig

  (* Representation of a job *)
  type t

  (* A convertor from jobrecord to the user-defined type t *)
  val f : record jobrec -> transaction t

  val depth : int

  val stdout_sz : int

end) :

sig

  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> blob -> transaction unit

  val monitor : jobref -> S.t -> transaction (aval S.t)

  val get : jobref -> transaction (record jobrec)

  val runNow : jobref -> string -> blob -> transaction (record jobrec)

  val lastLine : string -> string

end
