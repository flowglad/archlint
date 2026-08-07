module StringMap = Map.Make (String)
module StringSet = Set.Make (String)

type owner_index = StringSet.t StringMap.t

let owner_index owners =
  List.fold_left
    (fun index (unit_name, source_module) ->
      let source_modules =
        Option.value (StringMap.find_opt unit_name index) ~default:StringSet.empty
      in
      StringMap.add unit_name (StringSet.add source_module source_modules) index)
    StringMap.empty owners

let source_module_for_unit owners unit_name =
  match StringMap.find_opt unit_name owners with
  | Some source_modules when StringSet.cardinal source_modules = 1 ->
      Some (StringSet.choose source_modules)
  | _ -> None

let wrapped_unit_name head components =
  let separator = if String.ends_with ~suffix:"__" head then "" else "__" in
  head ^ separator ^ String.concat "__" components

let rec wrapped_owner owners head rev_prefix = function
  | [] -> None
  | component :: rest ->
      let rev_prefix = component :: rev_prefix in
      let more_specific = wrapped_owner owners head rev_prefix rest in
      (match more_specific with
      | Some _ -> more_specific
      | None ->
          source_module_for_unit owners
            (wrapped_unit_name head (List.rev rev_prefix)))

let split_last values =
  match List.rev values with
  | last :: reversed_prefix -> Some (List.rev reversed_prefix, last)
  | [] -> None

let canonicalize owners ~current_module path =
  match Path.flatten (Path.scrape_extra_ty path) with
  | `Contains_apply -> None
  | `Ok (head, suffixes) -> (
      match split_last suffixes with
      | None -> None
      | Some _ when not (Ident.persistent head) -> None
      | Some (qualifiers, symbol) ->
          let head_name = Ident.name head in
          let source_module =
            match wrapped_owner owners head_name [] qualifiers with
            | Some source_module -> Some source_module
            | None -> source_module_for_unit owners head_name
          in
          match source_module with
          | Some source_module when source_module <> current_module ->
              Some (source_module ^ "." ^ symbol)
          | Some _ | None -> None)
