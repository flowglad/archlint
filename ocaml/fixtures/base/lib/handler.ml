(* @archlint.module shell
   @archlint.domain demo.decision *)

let run path =
  let _exists = Unix.access path [ Unix.F_OK ] in
  Decision.decide 1
