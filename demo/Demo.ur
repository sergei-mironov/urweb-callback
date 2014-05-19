
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

structure Cat = CallbackNotify2.Make(struct 

  val cmd = "
    read f;
    case $f in
      /*) exit 1;;
      *..*) exit 2 ;;
      *ur|*urs) cat $f ;;
    esac ;
  "

  fun render j : transaction xbody =
    return <xml><pre>{[j.Stdout]}</pre></xml>

end)

fun viewsrc (s:string) : transaction page =
  template(
    n <- Cat.abortMore 30;
    jr <- Cat.create (Some (textBlob (s ^ "\n")));
    c <- Cat.monitor jr;
      return <xml>
        {c}
      </xml>)

structure Find = CallbackNotify2.Make(struct 

  val cmd = "find -type f -name '*urs' -or -name '*ur'"

  fun render j : transaction xbody =
      l <- forXM (lines j.Stdout) (fn s =>
        return <xml><a link={viewsrc s}>{[s]}</a><br/></xml>);
      return <xml>{l}</xml>

end)

fun main {} : transaction page =
  template(
    n <- Find.abortMore 30;
    jr <- Find.create None;
    j <- Find.monitor jr;
    return <xml>{j}</xml>)

fun status {} : transaction page =
  n <- Find.abortMore 0;
  return <xml>
    Jobs : {[n]}
    </xml>


