Urweb-callback
--------------

Urweb-callback is a library for managing asynchronous processes directly from an
[Ur/Web](http://www.impredicative.com/ur/) application. Online example should be accessible
[here](http://sthdwp.com/Demo2/main)


Installation
------------

Building requires [Nix](www.nixos.org/nix) package manager to be installed and
[urweb-build](http://github.com/grwlf/urweb-build) instruction set available
via NIX\_PATH variable.

        $ git clone https://github.com/grwlf/urweb-callback
        $ cd urweb-callback
        $ nix-build build.nix

The API
-------

Urweb-callback defines 3 levels of API. he first one is the CallbackFFI API which is
the low-level operations. In general, users should not use it. Callback and CallbackNotify
modules define the secons and third levels.

### Callback module

The poll-based functionality. Module provides Make and Default functors.

_Callback.Make_ functor acceppts the following parameters:

    (* Depth of garbage-collecting. All finished jobs older then current - gc_depth
     * will be removed *)
    val gc_depth : int

    (* Stdout buffer contains last stdout_sz lines *)
    val stdout_sz : int

    (* Callback to call upon job completion *)
    val callback : (record jobrec) -> transaction unit

_Callback.Default_ funtor calls Callback.Make with all default values.


The API is following:

    datatype eof = EOF

    datatype buffer = Chunk of blob * (option eof)

    type jobargs = {
        Cmd : string
      , Stdin : buffer
      , Args : list string
      }

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
    val createSync : jobargs -> transaction (record jobrec)

    (*
     * Feed more input to the job's stdin. It is an error to feed more data than
     * job's stdin buffer may hold. See Make's stdin_sz parameter.
     *)
    val feed : jobref -> buffer -> transaction unit

    (*
     * Get job's description structure
     *)
    val get : jobref -> transaction (record jobrec)

    (*
     * Aborts the transaction if the number of jobs exceeds the limit.
     * Returns the actual number of job objects in memory.
     *)
    val abortMore : int -> transaction int


### CallbackNotify module

CallbackNotify shows how to use callback argument of the Callaback.Make to implement client
notification. It adds to the Callback API the following functions:

    (*
     * Returns status of a job in a form of (channel * source)
     *)
    val monitor : jobref -> transaction jobstatus

    (*
     * Higher-level version of monitor. Takes 'render' function and returns the
     * XML representing job status.
     *)
    val monitorX : jobref -> (job -> xbody) -> transaction xbody


Example
-------

Below is an example appication demonstrating the Callback API usage. This application
starts the shell script which sleeps 2 second and then finds all files in the
current directory

    structure CB = Callback
    structure C = CallbackNotify.Default

    fun search (p:string) : transaction xbody =
      x <- C.abortMore 20;
      jr <- C.create (C.shellCommand ("sleep 2 ; find " ^ p ^ " -maxdepth 2"));
      C.monitorX jr (fn j =>
        case j.ExitCode of
          |Some _ => <xml><pre>{[j.Stdout]}</pre></xml>
          |None => <xml>Searching...</xml>)

    fun main {} : transaction page =
      s <- source <xml/>;
      return <xml>
        <head/>
        <body>
          <button value="Search files" onclick={fn _ =>
            x <- rpc(search ".");
            set s x
          }/>
          <hr/>
          <dyn signal={signal s}/>
        </body>
      </xml>


See test/, test2/ and demo/ folders for more examples.

Debugging
---------

To enable debug messages, set the UWCB\_DEBUG environment variable to some
value before runnung the application.

To run the stress-testing, 1) Start the ./test/Stress.exe 2) Run the ./stress.sh
from another terminal. 3) Kill the ./test/Stress.exe. There should be no
'Bye-bye' after the termination. If they are exist, there is a memory leak in
the code. Please, drop me a message about this.


Testing
-------

./test2 folder contains an automatic test script. To run the tests, do

    $ ./test2/run.sh

Upon completion, the script should print SUCCESS to the terminal. See
./test2/\*log files for testing logs.

Regards,
Sergey Mironov
grrwlf@gmail.com


