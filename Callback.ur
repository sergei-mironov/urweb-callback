
type jobref = CallbackFFI.jobref

con jobinfo = [
    Id = int
  , ExitCode = option int
  , Cmd = string
  , Hint = string
  ]

functor Make(M : sig

  con u

  constraint [Id,ExitCode,Cmd,Hint] ~ u

  table t : (jobinfo ++ u)

  sequence s

end) = struct

  open CallbackFFI

  type row' = record (jobinfo ++ M.u)

  (* fun ensql [avail ::_] (r : row') : $(map (sql_exp avail [] []) fs') = *)
  (*     @map2 [meta] [fst] [fn ts :: (Type * Type) => sql_exp avail [] [] ts.1] *)
  (*      (fn [ts] meta v => @sql_inject meta.Inj v) *)
  (*      M.folder M.cols r *)

  fun createSync (ji : record jobinfo, args : record M.u) : transaction (option int) =
    i <- nextval M.s;
    dml(insert M.t ({Id = sql_inject ji.Id,
          ExitCode = sql_inject ji.ExitCode,
          Cmd = sql_inject ji.Cmd,
          Hint = sql_inject ji.Hint} ++ args));

    return (Some i)

end


