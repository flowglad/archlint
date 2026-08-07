(* @archlint.module shell
   @archlint.domain wrapped.same-library *)

let run value =
  let _working_directory = Unix.getcwd () in
  Same_decision.decide value
