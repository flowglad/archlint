(* @archlint.module exempt
   @archlint.exempt-reason test-support *)

let int = 0

let add_test ~name:_ _args f = f 0
