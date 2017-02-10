table jobtable : (Callback.jobinfo ++ [Payload = int])
  PRIMARY KEY Id

sequence jobtable_seq

structure C = Callback.Make(
  struct
    con u = [Payload = int]
    val t = jobtable
    val s = jobtable_seq
  end
)

(* open Callback *)


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
  return <xml>
    <p>Callback template</p>
  </xml>)

