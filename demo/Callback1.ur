table jobtable : (Callback.jobinfo ++ [Payload=int])
  PRIMARY KEY Id

sequence jobtable_seq

structure C = Callback.Make(
  struct
    con u = [Payload = int]
    val t = jobtable
    val s = jobtable_seq

    fun completion (ji : record Callback.jobinfo) =
      return {}
  end
)


fun template (mb:transaction xbody) : transaction page =
  b <- mb;
  return
    <xml>
      <head/>
      <body>{b}</body>
    </xml>


fun main {} : transaction page = template (
  (* dml(INSERT INTO jobtable(Id,ExitCode,Cmd,Hint,Payload,Zzz) *)
  (*     VALUES(0,NULL,"","",0,0)); *)
  (* xx <- C.createSync "aaaa" {Payload=33} ; *)
  return <xml>
    <p>Callback template</p>
  </xml>)

