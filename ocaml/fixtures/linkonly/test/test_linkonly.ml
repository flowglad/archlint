(* @archlint.module test
   @archlint.domain demo.linkonly *)

let prop =
  QCheck2.Test.make ~name:"link" QCheck2.Gen.unit (fun () ->
      ignore Linkonly_core.decide_link;
      true)

let () = ignore prop
