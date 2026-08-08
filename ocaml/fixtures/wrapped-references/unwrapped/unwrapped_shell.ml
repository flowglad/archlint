(* @archlint.module shell
   @archlint.domain wrapped.unwrapped-library *)

let run value =
  let _working_directory = Unix.getcwd () in
  Unwrapped_decision.decide value
