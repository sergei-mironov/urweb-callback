
con jobrec = [JobRef = int, ExitCode = option int, Cmd = string, Stdout = string]

table jobs : $jobrec
  PRIMARY KEY JobRef

signature S = sig
  type jobref = CallbackFFI.jobref

  val nextjob : unit -> transaction jobref

  val create : jobref -> string -> blob -> transaction unit

  val get : jobref -> transaction (record jobrec)

  val runNow : jobref -> string -> blob -> transaction (record jobrec)

  val lastLine : string -> string
end

functor Make(S :
sig

  (* Depth of garbage-collecting. All finished jobs older then current - gc_depth
   * will be removed
   *)
  val gc_depth : int

  (* Stdout buffer contains last stdout_sz lines *)
  val stdout_sz : int

  (* Callback to call upon job completion *)
  val callback : (record jobrec) -> transaction unit

end) : S

structure Default : S

