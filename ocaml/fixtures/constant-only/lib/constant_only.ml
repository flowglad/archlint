(* @archlint.module core
   @archlint.domain demo.constant *)

let decide x =
  if x > 0 then `Positive else `Non_positive
