(* @archlint.module core
   @archlint.domain wrapped.unwrapped-library *)

let decide value =
  if value = 0 then `Zero else `Nonzero
