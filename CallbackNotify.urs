
con jobrec = [
    JobRef = int
  , ExitCode = option int
  , Cmd = string
  , Stdout = string
  , Stderr = string
  , ErrRep = string
  ]

type job = record jobrec

datatype jobstatus = Ready of job | Running of (channel job) * (source job)

type jobref = CallbackFFI.jobref

type jobargs = Callback.jobargs_

signature S = sig

  val nextJobRef : transaction jobref

  val create : jobargs -> transaction jobref

  val shellCommand : string -> jobargs

  val absCommand : string -> list string -> jobargs

  (*
   * Returns status of a job in a form of (channel * source)
   *)
  val monitor : jobref -> transaction jobstatus

  (*
   * Higher-level version of monitor. Takes 'render' function and returns the
   * XML representing job status.
   *)
  val monitorX : jobref -> (job -> xbody) -> transaction xbody

  (*
   * Aborts the handler if the number of jobs exceeds the limit.
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

end) : S

structure Default : S

