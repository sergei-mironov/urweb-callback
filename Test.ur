val gj = Callback.deref
val ref = Callback.ref

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun job_finishead (jr: Callback.jobref) : transaction page = 
  debug ("Test.ur: job finished" ^ (show (Callback.exitcode (gj jr))));
  return <xml/>

fun job_monitor (jr:Callback.jobref) : transaction page = template (
  let val j = Callback.deref jr in
  return <xml>
      Job : {[jr]}
      <br/>
      Pid : {[Callback.pid j]}
      <br/>
      ExitCode : {[Callback.exitcode j]}
      <br/>
      Stdout:  {[Callback.stdout j]}
      <br/>
      Errors:  {[Callback.errors j]}
    </xml>
  end)

fun job_start {} : transaction page =
  j <- Callback.create "for i in `seq 1 1 15`; do echo -n $i; sleep 2 ; done" "" 100 ;
  Callback.run j (url (job_finishead (ref j)));
  redirect (url (job_monitor (ref j)))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start a job</a>
    </xml>)
