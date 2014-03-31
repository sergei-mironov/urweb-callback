
fun lines (s:string) : list string =
  case String.split s #"\n" of
      None => []
    | Some (s1, s2) => s1 :: (lines s2)

fun forXM l f = List.mapXM f l

fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>

fun viewsrc (s:string) : transaction page =
  template (return <xml>
    Viewing {[s]}
  </xml>)

structure Find = CallbackNotify2.Make(struct 

  val cmd = "find -name '*urs' -or -name '*ur'"

  fun render j : transaction xbody =
      l <- forXM (lines j.Stdout) (fn s =>
        return <xml><a link={viewsrc s}>{[s]}</a><br/></xml>);
      return <xml>{l}</xml>

end)

fun job_monitor jr : transaction page =
  template (
    j <- Find.monitor jr;
    return <xml>{j}</xml>)

fun job_start {} : transaction page =
  jr <- Find.create None;
  redirect (url (job_monitor jr))

fun main {} : transaction page = template (
  return
    <xml>
      <a link={job_start {}}>Start the job</a>
    </xml>)


