
type jobref = CallbackFFI.jobref

con jobinfo = [
    Id = int
  , ExitCode = option int
  , Cmd = string
  , Hint = string
  ]

functor Make(M : sig

  con u

  val fu : folder u

  (* val injs : record (map sql_injectable u) *)

  constraint [Id,ExitCode,Cmd,Hint] ~ u

  table t : (jobinfo ++ u)

  sequence s

end) = struct

  open CallbackFFI

  fun createSync (cmd : string)
                 (injs : record (map sql_injectable M.u))
                 (fs : record M.u)
                 : transaction (option int) =

    i <- nextval M.s;

    dml (insert M.t (

        { Id = sql_inject i,
          ExitCode = sql_inject None,
          Cmd = sql_inject cmd,
          Hint = sql_inject "" } ++

        (@Top.map2 [sql_injectable] [ident] [sql_exp [] [] []]
          (fn [t] => @sql_inject) M.fu injs fs)
      )
    );

    return (Some i)

end


