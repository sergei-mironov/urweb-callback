
structure C = CallbackNotify2.Make(struct 
  fun render j : transaction xbody =
    return
      <xml>
        <div>
        Job : {[j.JobRef]}
        <br/>
        ExitCode : {[j.ExitCode]}
        <br/>
        Stdout:  {[j.Stdout]}
        </div>
      </xml>
end)

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun job_monitor (jr:C.jobref) : transaction page =
  template (
    j <- C.monitor jr;
    return <xml>{j}</xml>)

fun job_start {} : transaction page =
  jr <- C.nextjob {};
  C.create jr "find -name '*urs' -or -name '*ur'" None;
  redirect (url (job_monitor jr))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start a sleep job</a>
    </xml>)


