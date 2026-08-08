let path head suffixes =
  List.fold_left
    (fun path suffix -> Path.Pdot (path, suffix))
    (Path.Pident (Ident.create_persistent head))
    suffixes

let expect owners ~current_module path expected =
  let actual = Qualified_reference.canonicalize owners ~current_module path in
  if actual <> expected then
    failwith
      (Printf.sprintf "expected %s, got %s"
         (Option.value expected ~default:"<none>")
         (Option.value actual ~default:"<none>"))

let () =
  let owners =
    Qualified_reference.owner_index
      [
        ("Wrapper__Decision", "Decision");
        ("Same_wrapper__Shell", "Shell");
        ("Unwrapped", "Unwrapped");
      ]
  in
  (* Public wrapper aliases and Dune's internal compilation-unit paths have the
     same evaluator representation. *)
  expect owners ~current_module:"Shell"
    (path "Wrapper" [ "Decision"; "decide" ])
    (Some "Decision.decide");
  expect owners ~current_module:"Shell"
    (path "Wrapper__Decision" [ "decide" ])
    (Some "Decision.decide");
  (* Dune may expose wrapper aliases through [-open Wrapper__]. *)
  expect owners ~current_module:"Shell"
    (path "Wrapper__" [ "Decision"; "decide" ])
    (Some "Decision.decide");
  (* Unwrapped compilation units retain their existing representation. *)
  expect owners ~current_module:"Shell" (path "Unwrapped" [ "decide" ])
    (Some "Unwrapped.decide");
  (* Canonical ownership, rather than the wrapper spelling, excludes self
     references. *)
  expect owners ~current_module:"Decision"
    (path "Wrapper" [ "Decision"; "decide" ])
    None;
  expect owners ~current_module:"Decision"
    (path "Wrapper__Decision" [ "decide" ])
    None;
  expect owners ~current_module:"Unwrapped" (path "Unwrapped" [ "decide" ])
    None;
  (* A source module with a matching short name is insufficient evidence for
     an unrelated wrapper or dependency. *)
  expect owners ~current_module:"Shell"
    (path "Dependency" [ "Decision"; "decide" ])
    None;
  expect owners ~current_module:"Shell" (path "Decision" [ "decide" ]) None;
  expect owners ~current_module:"Shell"
    (Path.Pdot (Path.Pident (Ident.create_local "Wrapper__Decision"), "decide"))
    None;
  let ambiguous =
    Qualified_reference.owner_index
      [ ("Shared", "First"); ("Shared", "Second") ]
  in
  expect ambiguous ~current_module:"Shell" (path "Shared" [ "decide" ]) None;
  expect owners ~current_module:"Shell"
    (Path.Pdot
       ( Path.Papply
           ( Path.Pident (Ident.create_persistent "Functor"),
             Path.Pident (Ident.create_persistent "Argument") ),
         "decide" ))
    None
