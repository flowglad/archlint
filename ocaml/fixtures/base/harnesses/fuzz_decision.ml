(* @archlint.module test
   @archlint.domain demo.decision *)

let register_fuzz_property () =
  Crowbar.add_test ~name:"dependency-defined test scope" [ Crowbar.int ] (fun x ->
      ignore (Decision.decide x))

let () = register_fuzz_property ()
