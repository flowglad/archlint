(* @archlint.module shell
   @archlint.domain wrapped.cross-library *)

let run () =
  let _working_directory = Unix.getcwd () in
  Decision.decide false
