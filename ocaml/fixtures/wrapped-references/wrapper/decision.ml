(* @archlint.module core
   @archlint.domain wrapped.cross-library *)

let decide value =
  if value then `Accepted else `Rejected
