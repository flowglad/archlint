(* @archlint.module stateTest
   @archlint.domain demo.decision *)

let suite =
  [
    QCheck2.Test.make ~name:"operation sequence"
      QCheck2.Gen.(list small_int)
      (fun xs -> List.for_all (fun x -> match Decision.decide x with _ -> true) xs);
  ]
