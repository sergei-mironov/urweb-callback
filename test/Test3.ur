structure C = Callback.Make(
  struct
    val f = fn x => return (<xml>{[x.Stdout]}</xml> : xbody)
  end)

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun job_monitor (jr:C.jobref) : transaction page = template (
  e <- C.exitcode jr;
  o <- C.stdout jr;
  return <xml>
      Job : {[jr]}
      <br/>
      ExitCode : {[e]}
      <br/>
      Stdout:  {[o]}
    </xml>)

fun job_start {} : transaction page =
  jr <- C.create "for i in `seq 1 1 5`; do echo -n $i; sleep 2 ; done" "";
  redirect (url (job_monitor jr))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start a sleep job</a>
    </xml>)
