val gj = CallbackFFI.deref
val ref = CallbackFFI.ref

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun job_finishead (jr: CallbackFFI.jobref) : transaction page = 
  debug ("Test.ur: job finished" ^ (show jr));
  return <xml/>

fun job_monitor (jr:CallbackFFI.jobref) : transaction page = template (
  j <- CallbackFFI.deref jr;
  return <xml>
      Job : {[jr]}
      <br/>
      Pid : {[CallbackFFI.pid j]}
      <br/>
      ExitCode : {[CallbackFFI.exitcode j]}
      <br/>
      Stdout:  {[CallbackFFI.stdout j]}
      <br/>
      Errors:  {[CallbackFFI.errors j]}
    </xml>)

sequence jobrefs

fun job_start {} : transaction page =
  jr <- nextval jobrefs;
  j <- CallbackFFI.create "for i in `seq 1 1 15`; do echo -n $i; sleep 2 ; done" 100 jr;
  CallbackFFI.run j (textBlob "") (url (job_finishead (ref j)));
  redirect (url (job_monitor (ref j)))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start a sleep job</a>
    </xml>)
