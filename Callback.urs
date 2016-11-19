
con jobinfo = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , ErrRep = string
  ]

con jobrec = jobinfo ++ [
    Stdout = blob
  , Stderr = blob
  , InMemory = bool
  ]

table jobs : $jobinfo
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

  (* Contructor for jobargs: prepare a shell command. Programmer is responsible
   * for keeping this line safe for the system
   *)
  val shellCommand : string -> jobargs

  (*
   * Contructor for jobargs: takes an absolute path to the executable and a list
   * of arguments. This is the required way of calling jobs.
   *)
  val absCommand : string -> (list string) -> jobargs

  (*
   * Constructor for buffer. Makes a buffer from a string
   *)
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
  val createSync : jobargs -> transaction (record jobinfo)

  (*
   * Feed more input to the job's stdin. It is an error to feed more data than
   * job's stdin buffer may hold. See Make's stdin_sz parameter.
   *)
  val feed : jobref -> buffer -> transaction unit

  (*
   * Get job's description structure
   *)
  val get : jobref -> transaction (record jobinfo)

  (*
   * Aborts the transaction if the number of jobs exceeds the limit.
   * Returns the actual number of job objects in memory.
   *)
  val abortMore : int -> transaction int

end

functor Make(S :
sig

  (* Depth of garbage-collecting. All finished jobs older then (current - gc_depth)
   * will be removed
   *)
  val gc_depth : int

  (* The size of Stdout and Stderr buffers. Buffers are 'scrolling', that means
   * they contain last stdout_sz bytes of job's output
   *)
  val stdout_sz : int

  (* Stdin buffer size. [feed] will restart the transaction on overflow *)
  val stdin_sz : int

  (* Callback to call upon job completion *)
  val callback : (record jobinfo) -> transaction unit

end) : S

structure Default : S


(** Helper string utilities **)

val lastLines : int -> blob -> string

val blobLines : blob -> string

val checkString : (string -> bool) -> string -> transaction string

