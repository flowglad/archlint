(* @archlint.module test
   @archlint.domain demo.constant *)

let suite =
  [
    QCheck2.Test.make ~name:"constant assertion"
      QCheck2.Gen.unit
      (fun () -> match Constant_only.decide 1 with _ -> true);
  ]
