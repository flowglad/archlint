(* @archlint.module state
   @archlint.domain demo.decision *)

module Counter = struct
  let cell = Atomic.make 0
end

let read () =
  Decision.decide (Atomic.get Counter.cell)
