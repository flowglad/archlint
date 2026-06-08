(* @archlint.module shell
   @archlint.domain demo.decision *)

open Js_of_ocaml

let () =
  Js.export "demo"
    Decision.decide
