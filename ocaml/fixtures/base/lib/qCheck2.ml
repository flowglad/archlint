(* @archlint.module exempt
   @archlint.exempt-reason test-support *)

module Gen = struct
  type 'a t = unit

  let list (_ : 'a t) : 'a list t = ()
  let map (_ : 'a -> 'b) (_ : 'a t) : 'b t = ()
  let int : int t = ()
  let small_int : int t = ()
  let unit : unit t = ()
end

module Test = struct
  let make ~name:_ (_ : 'a Gen.t) (_ : 'a -> bool) = ()
  let check_exn _ = ()
end
