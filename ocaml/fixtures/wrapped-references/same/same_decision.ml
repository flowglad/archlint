(* @archlint.module core
   @archlint.domain wrapped.same-library *)

let decide value =
  if value > 0 then `Accepted else `Rejected
