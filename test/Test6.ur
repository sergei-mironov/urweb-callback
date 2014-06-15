
structure C = CallbackNotify

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun render (j:C.job) : xbody =
    <xml>
      <div>
      Job : {[j.JobRef]}
      <br/>
      ExitCode : {[j.ExitCode]}
      <br/>
      Stdout:  {[j.Stdout]}
      </div>
    </xml>

fun job_monitor (jr:C.jobref) : transaction page =
  template (
    n <- C.abortMore 30;
    x <- C.monitorX jr render;
    return <xml>
      Job <br/> {x} <br/>
      Nactive : {[n]}
    </xml>
    )

fun job_start {} : transaction page =
  jr <- C.create (C.shellCommand "for i in `seq 1 1 5`; do echo -n $i; sleep 2 ; done");
  redirect (url (job_monitor jr))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start a sleep job</a>
    </xml>)

