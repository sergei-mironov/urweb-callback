
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  , Stderr = string
  , ErrRep = string
  ]

table jobs : $jobrec
  PRIMARY KEY JobRef

datatype eof = EOF

datatype buffer = Chunk of blob * (option eof)

type jobargs_ = {
    Cmd : string
  , Stdin : buffer
  , Args : list string
  }

signature S = sig

  (** Arguments API **)

  type jobargs = jobargs_

  val shellCommand : string -> jobargs

  val mkBuffer : string -> buffer

  (** Job API **)

  type jobref = CallbackFFI.jobref

  (* Generate uniq jobref *)
  val nextJobRef : transaction jobref

  (* Simply create the job *)
  val create : jobargs -> transaction jobref

  (*
   * Create the job using existing jobref and the set of arguments. Jobref
   * should be uniq within the application
   *)
  val createWithRef : jobref -> jobargs -> transaction unit

  (*
   * Create the job and run it immideately
   *)
  val createSync : jobargs -> transaction (record jobrec)

  (*
   * Feed more input to the job's stdin
   *)
  val feed : jobref -> buffer -> transaction unit

  val get : jobref -> transaction (record jobrec)

  (*
   * Aborts the transaction if the number of jobs exceeds the limit.
   * Returns the actual number of job objects in memory.
   *)
  val abortMore : int -> transaction int


  (** String utilities **)

  val lastLines : int -> string -> string

  val checkString : (string -> bool) -> string -> transaction string

end

functor Make(S :
sig

  (* Depth of garbage-collecting. All finished jobs older then current - gc_depth
   * will be removed
   *)
  val gc_depth : int

  (* Stdout buffer contains last stdout_sz bytes *)
  val stdout_sz : int

  (* Stdin buffer size. [feed] will restart the transaction on overflow *)
  val stdin_sz : int

  (* Callback to call upon job completion *)
  val callback : (record jobrec) -> transaction unit

end) : S

structure Default : S

