(* @archlint.module test
   @archlint.domain demo.preprocessed *)

let prop =
  QCheck2.Test.make ~name:"preprocessed core"
    QCheck2.Gen.small_int
    (fun x -> Preprocessed_core.decide_preprocessed x || x < 0)

let () = ignore prop
