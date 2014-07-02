Urweb-callback
--------------

Urweb-callback is a library for managing asynchronous processes directly from an
[Ur/Web](http://www.impredicative.com/ur/) application.


Installation
------------

Urweb-callback requires certain patches to be applied over the Ur/Web compiler.
Follow the instructions below:

1. Obtain the sources and prepare the patches

        $ hg clone http://hg.impredicative.com/urweb
        $ git clone https://github.com/grwlf/urweb-callback
        $ cp -t urweb urweb-callback/*patch

2. Build the Ur/Web compiler. You may try the latest Ur/Web from the official
   repo. In case it doesn't work, please test the known-good revision (see
   below).

        $ cd urweb

              # (skip this line to stay on latets Ur/Web)
        $ hg checkout a3435112b83e
    
        $ ./autogen.sh
        $ ./configure
        $ make install
        $ cd ..

3. Build the urweb-callback
 
        $ cd urweb-callback
        $ make
     
Note: gcc supporting C++11 is required to compile the library.


The API
-------

Urweb-callback defines 3 levels of API. he first one is the CallbackFFI API which is
the low-level operations. In general, users should not use it. Callback and CallbackNotify
modules define the secons and third levels.

### Callback module

The second level is 
defined in the Callback.ur module via Make functor. 

_Callback.Make_ functor acceppts the following parameters:

    (* Depth of garbage-collecting. All finished jobs older then current - gc_depth
     * will be removed *)
    val gc_depth : int

    (* Stdout buffer contains last stdout_sz lines *)
    val stdout_sz : int

    (* Callback to call upon job completion *)
    val callback : (record jobrec) -> transaction unit

_Callback.Default_ funtor calls Callback.Make with all default values.

The most important functions returned by Make are:

      (** Arguments API **)

      type jobargs = {
          Cmd : string
        , Stdin : buffer
        , Args : list string
        }

      con jobrec = [
          JobRef = int
        , ExitCode = option int
        , Cmd = string
        , Stdout = string
        , ErrRep = string
        ]


      val shellCommand : string -> jobargs

      val mkBuffer : string -> buffer

      (** Job API **)

      type jobref = int

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

      (* Utility: take the multy-line string and return the very last line *)
      val lastLine : string -> string

      (*
       * Aborts the transaction if the number of jobs exceeds the limit.
       * Returns the actual number of job objects in memory.
       *)
      val abortMore : int -> transaction int


`nextjob` issues unique job references, `create` accepts the following arguments:
jobref, command line, stdin, then runs the process. `get` returns it's state.

`runNow` creates the procees and runs it synchronously. This function blocks
Ur/Web's handler thread. Use it at your own risk.

### CallbackNotify module

CallbackNotify shows how to use callback argument of the Callaback.Make to implement client
notification. It is able to send the job state over Ur/Web channels. See test/Test6.ur for
an example.

Usage
-----

Below is an example appication demonstrating the Callback API usage. This application 
starts the shell script which counts from 1 to 5.

    structure C = Callback.Default

    fun template (mb:transaction xbody) : transaction page =
      b <- mb;
      return
        <xml>
          <head/>
          <body>{b}</body>
        </xml>

    fun monitor (jr:C.jobref) : transaction page = T.template (
      j <- C.get jr;
      return <xml>{[j.Stdout]}</xml>)

    fun main (i:int) : transaction page = T.template (
      x <- C.abortMore 20;
      jr <- C.create (C.shellCommand ("sleep " ^ show i));
      redirect (url (monitor jr)))

    fun cnt {} : transaction page = T.template (
      x <- C.abortMore 20;
      return <xml>{[x]}</xml>)

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


