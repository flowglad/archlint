(* @archlint.module test
   @archlint.domain demo.decision *)

let failures = ref 0

let check name cond =
  if cond then Stdlib.Printf.printf "ok: %s\n" name
  else (
    Stdlib.incr failures;
    Stdlib.Printf.printf "FAIL: %s\n" name)

let () =
  check "decide is positive" (match Decision.decide 1 with `Positive -> true | _ -> false);
  if !failures > 0 then Stdlib.exit 1
