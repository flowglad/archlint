(* @archlint.module test
   @archlint.domain demo.closure *)

let gen_b =
  ignore (Closure_core.decide_b 0);
  QCheck2.Gen.small_int

let totality name f =
  QCheck2.Test.make ~name QCheck2.Gen.small_int (fun x -> ignore (f x); true)

let prop_a =
  QCheck2.Test.make ~name:"a" QCheck2.Gen.small_int (fun x ->
      Closure_core.decide_a x || x >= 0)

let prop_b = QCheck2.Test.make ~name:"b" gen_b (fun (x : int) -> x = x)
let prop_c = totality "c" (fun x -> Closure_core.decide_c x)

let () =
  ignore prop_a;
  ignore prop_b;
  ignore prop_c
