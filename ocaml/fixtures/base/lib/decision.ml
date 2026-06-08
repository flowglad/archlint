(* @archlint.module core
   @archlint.domain demo.decision *)

let decide x =
  if x > 0 then `Positive else `Non_positive
