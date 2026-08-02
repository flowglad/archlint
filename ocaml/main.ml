open Stdlib
open Parsetree
open Asttypes
open Longident

module StringSet = Set.Make (String)
module StringMap = Map.Make (String)

type metadata = {
  module_type : string;
  domain : string;
  exempt_reason : string;
}

type generated_input = { name : string; uses : string list }
type operation_sequence = {
  input : string;
  operations : string list;
  assertions : string list;
}
type property_check = {
  references : string list;
  generated_inputs : generated_input list;
  operation_sequences : operation_sequence list;
}
type shared_state = { kind : string; references : string list }

type interface_logic_evidence = {
  function_bodies : string list;
  constructor_bodies : string list;
  derived_value_bodies : string list;
  control_flow : string list;
  imperative_declarations : string list;
}

type file_fact = {
  path : string;
  test_scope : string;
  metadata : metadata;
  imports : string list;
  identifiers : string list;
  api_references : string list;
  decision_surface : string list;
  property_test_surface : string list;
  decision_products : string list;
  decision_references : string list;
  module_name : string;
  qualified_references : string list;
  effectful_imports : string list;
  effectful_identifiers : string list;
  shared_state : shared_state list;
  property_checks : property_check list;
  interface_logic_evidence : interface_logic_evidence;
}

type interface_exports = {
  exported_values : StringSet.t;
  exported_references : StringSet.t;
}

type typedtree_artifact = {
  artifact_path : string;
  source_path : string;
  load_path_visible : string list;
  load_path_hidden : string list;
}

type facts = {
  mutable imports : StringSet.t;
  mutable identifiers : StringSet.t;
  mutable api_references : StringSet.t;
  mutable decision_surface : StringSet.t;
  mutable property_test_surface : StringSet.t;
  mutable decision_products : StringSet.t;
  mutable decision_references : StringSet.t;
  mutable qualified_references : StringSet.t;
  mutable effectful_identifiers : StringSet.t;
  mutable shared_state : StringSet.t StringMap.t;
  mutable property_checks : property_check list;
  mutable function_references : StringSet.t StringMap.t;
  mutable function_bodies : StringSet.t;
  mutable constructor_bodies : StringSet.t;
  mutable derived_value_bodies : StringSet.t;
  mutable control_flow : StringSet.t;
  mutable imperative_declarations : StringSet.t;
}

let empty_facts () =
  {
    imports = StringSet.empty;
    identifiers = StringSet.empty;
    api_references = StringSet.empty;
    decision_surface = StringSet.empty;
    property_test_surface = StringSet.empty;
    decision_products = StringSet.empty;
    decision_references = StringSet.empty;
    qualified_references = StringSet.empty;
    effectful_identifiers = StringSet.empty;
    shared_state = StringMap.empty;
    property_checks = [];
    function_references = StringMap.empty;
    function_bodies = StringSet.empty;
    constructor_bodies = StringSet.empty;
    derived_value_bodies = StringSet.empty;
    control_flow = StringSet.empty;
    imperative_declarations = StringSet.empty;
  }

let add set value =
  if value = "" then set else StringSet.add value set

let add_identifier facts value = facts.identifiers <- add facts.identifiers value
let add_api_reference facts value = facts.api_references <- add facts.api_references value
let add_optional_identifier facts = function
  | Some value -> add_identifier facts value
  | None -> ()
let is_bindable_name name =
  name <> "()" && name <> "[]" && name <> "::"

let add_shared_state facts ~kind ~reference =
  let references =
    match StringMap.find_opt kind facts.shared_state with
    | Some refs -> refs
    | None -> StringSet.empty
  in
  facts.shared_state <- StringMap.add kind (add references reference) facts.shared_state

let rec longident_parts = function
  | Lident name -> [ name ]
  | Ldot (prefix, name) -> longident_parts prefix.txt @ [ name.txt ]
  | Lapply (left, right) -> longident_parts left.txt @ longident_parts right.txt

let longident_last ident =
  match List.rev (longident_parts ident) with
  | head :: _ -> head
  | [] -> ""

let longident_text ident = String.concat "." (longident_parts ident)

let lid_parts lid = longident_parts lid.txt
let lid_last lid = longident_last lid.txt
let lid_text lid = longident_text lid.txt

let set_to_list set = StringSet.elements set

let sorted_unique values =
  values |> List.fold_left add StringSet.empty |> set_to_list

let basename_without_extension path =
  let base = Filename.basename path in
  try Filename.chop_extension base with Invalid_argument _ -> base

let absolute_path path =
  if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path

let module_name_of_path path =
  basename_without_extension path
  |> String.split_on_char '_'
  |> List.map (fun part ->
         if part = "" then ""
         else
           String.uppercase_ascii (String.sub part 0 1)
           ^ String.sub part 1 (String.length part - 1))
  |> String.concat ""

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
      let length = in_channel_length channel in
      really_input_string channel length)

let parse_metadata source =
  let module_type = ref "" in
  let domain = ref "" in
  let exempt_reason = ref "" in
  let seen_module_type = ref false in
  let seen_domain = ref false in
  let seen_exempt_reason = ref false in
  let duplicate_module_type = ref false in
  let duplicate_domain = ref false in
  let duplicate_exempt_reason = ref false in
  let length = String.length source in
  let rec skip_ws index =
    if index >= length then index
    else
      match source.[index] with
      | ' ' | '\t' | '\r' | '\n' -> skip_ws (index + 1)
      | _ -> index
  in
  let rec find_comment_end depth index =
    if index + 1 >= length then None
    else if source.[index] = '(' && source.[index + 1] = '*' then
      find_comment_end (depth + 1) (index + 2)
    else if source.[index] = '*' && source.[index + 1] = ')' then
      if depth = 1 then Some index else find_comment_end (depth - 1) (index + 2)
    else find_comment_end depth (index + 1)
  in
  let record_line line =
    let trimmed = String.trim line in
    match String.split_on_char ' ' trimmed |> List.filter (( <> ) "") with
    | [ "@archlint.module"; value ] ->
        if !seen_module_type then duplicate_module_type := true;
        seen_module_type := true;
        module_type := value
    | [ "@archlint.domain"; value ] ->
        if !seen_domain then duplicate_domain := true;
        seen_domain := true;
        domain := value
    | [ "@archlint.exempt-reason"; value ] ->
        if !seen_exempt_reason then duplicate_exempt_reason := true;
        seen_exempt_reason := true;
        exempt_reason := value
    | _ -> ()
  in
  let rec consume index =
    let index = skip_ws index in
    if index + 1 < length && source.[index] = '(' && source.[index + 1] = '*'
    then
      match find_comment_end 1 (index + 2) with
      | None -> ()
      | Some stop ->
          let body = String.sub source (index + 2) (stop - index - 2) in
          List.iter record_line (String.split_on_char '\n' body);
          consume (stop + 2)
    else ()
  in
  consume 0;
  {
    module_type = (if !duplicate_module_type then "" else !module_type);
    domain = (if !duplicate_domain then "" else !domain);
    exempt_reason = (if !duplicate_exempt_reason then "" else !exempt_reason);
  }

let effectful_imports =
  StringSet.of_list
    [
      "Cohttp";
      "Cohttp_eio";
      "Eio";
      "Eio_main";
      "Eio_unix";
      "Js_of_ocaml";
      "Mirage_crypto_rng_unix";
      "Sys";
      "Unix";
      "X509";
    ]

let effectful_identifiers =
  StringSet.of_list
    [
      "Eio";
      "Eio_main";
      "Eio_unix";
      "In_channel";
      "Js";
      "Js_of_ocaml";
      "Out_channel";
      "Sys";
      "Unix";
    ]

let test_library_identifiers =
  StringSet.of_list
    [
      "Alcotest";
      "Crowbar";
      "Expect_test";
      "Ppx_inline_test";
      "QCheck";
      "QCheck2";
      "QCheck_alcotest";
    ]

let state_type_identifiers =
  StringSet.of_list [ "Atomic"; "Condition"; "Hashtbl"; "Mutex"; "Queue"; "Semaphore"; "Stack" ]

let record_longident facts lid =
  let parts = lid_parts lid in
  List.iter (add_identifier facts) parts;
  add_api_reference facts (lid_last lid);
  List.iter
    (fun part ->
      if StringSet.mem part test_library_identifiers then facts.api_references <- add facts.api_references part;
      if StringSet.mem part effectful_identifiers then
        facts.effectful_identifiers <- add facts.effectful_identifiers part)
    parts

let record_typedtree_reference facts ~current_module ~owner_modules path =
  match Path.flatten (Path.scrape_extra_ty path) with
  | `Contains_apply -> ()
  | `Ok (head, suffixes) -> (
      let owner_module = Ident.name head in
      match List.rev suffixes with
      | symbol :: _
        when owner_module <> current_module
             && StringSet.mem owner_module owner_modules ->
          facts.qualified_references <-
            add facts.qualified_references (owner_module ^ "." ^ symbol)
      | _ -> ())

let collect_typedtree_qualified_references ~current_module ~owner_modules artifact =
  let facts = empty_facts () in
  let record = record_typedtree_reference facts ~current_module ~owner_modules in
  let iterator =
    {
      Tast_iterator.default_iterator with
      expr =
        (fun self expression ->
          (match expression.Typedtree.exp_desc with
          | Typedtree.Texp_ident (path, _, _) -> record path
          | Typedtree.Texp_new (path, _, _) -> record path
          | Typedtree.Texp_instvar (_, path, _)
          | Typedtree.Texp_setinstvar (_, path, _, _) ->
              record path
          | _ -> ());
          Tast_iterator.default_iterator.expr self expression);
      typ =
        (fun self core_type ->
          (match core_type.Typedtree.ctyp_desc with
          | Typedtree.Ttyp_constr (path, _, _)
          | Typedtree.Ttyp_class (path, _, _)
          | Typedtree.Ttyp_open (path, _, _) ->
              record path
          | _ -> ());
          Tast_iterator.default_iterator.typ self core_type);
      module_expr =
        (fun self module_expr ->
          (match module_expr.Typedtree.mod_desc with
          | Typedtree.Tmod_ident (path, _) -> record path
          | _ -> ());
          Tast_iterator.default_iterator.module_expr self module_expr);
      module_type =
        (fun self module_type ->
          (match module_type.Typedtree.mty_desc with
          | Typedtree.Tmty_ident (path, _)
          | Typedtree.Tmty_alias (path, _) ->
              record path
          | Typedtree.Tmty_with (module_type, constraints) ->
              List.iter
                (fun (path, _, _) -> record path)
                constraints;
              Tast_iterator.default_iterator.module_type self module_type
          | _ -> ());
          Tast_iterator.default_iterator.module_type self module_type);
    }
  in
  let rec iter_binary_annots = function
    | Cmt_format.Implementation structure -> iterator.structure iterator structure
    | Cmt_format.Interface signature -> iterator.signature iterator signature
    | Cmt_format.Partial_implementation parts | Cmt_format.Partial_interface parts ->
        Array.iter iter_binary_part parts
    | Cmt_format.Packed _ -> ()
  and iter_binary_part = function
    | Cmt_format.Partial_structure structure -> iterator.structure iterator structure
    | Cmt_format.Partial_structure_item item -> iterator.structure_item iterator item
    | Cmt_format.Partial_expression expression -> iterator.expr iterator expression
    | Cmt_format.Partial_pattern (_, pattern) -> iterator.pat iterator pattern
    | Cmt_format.Partial_class_expr class_expr -> iterator.class_expr iterator class_expr
    | Cmt_format.Partial_signature signature -> iterator.signature iterator signature
    | Cmt_format.Partial_signature_item item -> iterator.signature_item iterator item
    | Cmt_format.Partial_module_type module_type ->
        iterator.module_type iterator module_type
  in
  let cmt = Cmt_format.read_cmt artifact.artifact_path in
  iter_binary_annots cmt.Cmt_format.cmt_annots;
  facts.qualified_references

let record_state_type_reference facts lid =
  let parts = lid_parts lid in
  if List.exists (fun part -> StringSet.mem part state_type_identifiers) parts then
    add_shared_state facts ~kind:"ocaml-shared-state" ~reference:(lid_text lid)

let is_state_constructor_name name =
  List.mem name [ "create"; "init"; "make" ]

let expression_contains_state_allocation expression =
  let found = ref false in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
          (match expression.pexp_desc with
          | Pexp_apply ({ pexp_desc = Pexp_ident lid; _ }, _) -> (
              match List.rev (lid_parts lid) with
              | "ref" :: _ -> found := true
              | "create" :: "Hashtbl" :: _ -> found := true
              | "create" :: "Mutex" :: _ -> found := true
              | "make" :: "Atomic" :: _ -> found := true
              | "create" :: "Queue" :: _ -> found := true
              | "create" :: "Stack" :: _ -> found := true
              | _ -> ())
          | _ -> ());
          Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression;
  !found

let module_expr_ident_name module_expr =
  match module_expr.pmod_desc with
  | Pmod_ident lid -> Some (lid_last lid)
  | _ -> None

let module_type_ident_name module_type =
  match module_type.pmty_desc with
  | Pmty_ident lid -> Some (lid_last lid)
  | _ -> None

let pattern_names pattern =
  let names = ref StringSet.empty in
  let iterator =
    {
      Ast_iterator.default_iterator with
      pat =
        (fun self pattern ->
        (match pattern.ppat_desc with
        | Ppat_var name -> names := add !names name.txt
        | Ppat_alias (_, name) -> names := add !names name.txt
        | Ppat_construct (lid, _) ->
            names := add !names (lid_last lid)
        | _ -> ());
        Ast_iterator.default_iterator.pat self pattern);
    }
  in
  iterator.pat iterator pattern;
  !names

let rec expression_is_function expression =
  match expression.pexp_desc with
  | Pexp_function _ -> true
  | Pexp_constraint (inner, _) | Pexp_coerce (inner, _, _) -> expression_is_function inner
  | _ -> false

let rec expression_contains_operation_sequence_generator expression =
  let found = ref false in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
        (match expression.pexp_desc with
        | Pexp_ident lid -> (
            match lid_last lid with
            | "array" | "array_of_size" | "list" | "list_size" | "list_repeat" | "list_small" ->
                found := true
            | _ -> ())
        | _ -> ());
        Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression;
  !found

let api_references_in_expression expression =
  let references = ref StringSet.empty in
  let record lid =
    references := add !references (lid_last lid);
    List.iter
      (fun part ->
        if StringSet.mem part test_library_identifiers then references := add !references part)
      (lid_parts lid)
  in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
        (match expression.pexp_desc with
        | Pexp_apply ({ pexp_desc = Pexp_ident lid; _ }, _) -> record lid
        | Pexp_ident lid -> record lid
        | Pexp_construct (lid, _) -> record lid
        | Pexp_field (_, lid) -> record lid
        | Pexp_setfield (_, lid, _) -> record lid
        | _ -> ());
        Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression;
  !references

let is_property_test_call called =
  match called.pexp_desc with
  | Pexp_ident lid -> (
      match List.rev (lid_parts lid) with
      | "make" :: "Test" :: _ -> true
      | "make" :: "QCheck" :: _ -> true
      | _ -> false)
  | _ -> false

let function_body_argument args =
  args |> List.rev
  |> List.find_map (fun (_label, expression) ->
         if expression_is_function expression then Some expression else None)

let rec function_argument_patterns expression =
  match expression.pexp_desc with
  | Pexp_function (params, _, body) ->
      let param_patterns =
        params
        |> List.filter_map (fun param ->
               match param.pparam_desc with
               | Pparam_val (_, _, pattern) -> Some pattern
               | Pparam_newtype _ -> None)
      in
      let body_patterns =
        match body with
        | Pfunction_body body -> function_argument_patterns body
        | Pfunction_cases (cases, _, _) ->
            cases
            |> List.concat_map (fun case ->
                   case.pc_lhs :: function_argument_patterns case.pc_rhs)
      in
      param_patterns @ body_patterns
  | Pexp_constraint (inner, _) | Pexp_coerce (inner, _, _) -> function_argument_patterns inner
  | _ -> []

let rec expanded_api_references facts references visited =
  StringSet.fold
    (fun reference acc ->
      if StringSet.mem reference visited then add acc reference
      else
        let visited = add visited reference in
        let direct = add acc reference in
        match StringMap.find_opt reference facts.function_references with
        | None -> direct
        | Some helper_references ->
            StringSet.union direct (expanded_api_references facts helper_references visited))
    references StringSet.empty

let expression_contains_identifier name expression =
  let found = ref false in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
        (match expression.pexp_desc with
        | Pexp_ident lid when lid_last lid = name -> found := true
        | _ -> ());
        Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression;
  !found

let generated_input_uses body name =
  if expression_contains_identifier name body then [ name ] else []

let generated_input_api_uses facts body name =
  let uses = ref StringSet.empty in
  let record expression =
    if expression_contains_identifier name expression then
      uses :=
        StringSet.union !uses
          (expanded_api_references facts
             (api_references_in_expression expression)
             StringSet.empty)
  in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
        (match expression.pexp_desc with
        | Pexp_apply _ -> record expression
        | _ -> ());
        Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator body;
  set_to_list !uses

let generated_inputs_for_property facts body =
  function_argument_patterns body
  |> List.concat_map (fun pattern ->
         pattern_names pattern |> StringSet.elements
         |> List.filter is_bindable_name
         |> List.map (fun name -> { name; uses = generated_input_uses body name }))

let operation_sequences_for_property facts body args generated_inputs =
  if
    List.exists
      (fun (_label, argument) -> expression_contains_operation_sequence_generator argument)
      args
  then
    let assertions =
      expanded_api_references facts (api_references_in_expression body) StringSet.empty
      |> set_to_list
    in
    generated_inputs
    |> List.filter (fun input -> input.uses <> [])
    |> List.filter_map (fun input ->
           let operations = generated_input_api_uses facts body input.name in
           if operations = [] then None
           else Some { input = input.name; operations; assertions })
  else []

let rec collect_structure_item facts item =
  match item.pstr_desc with
  | Pstr_open open_decl ->
      Option.iter
        (fun name -> facts.imports <- add facts.imports name)
        (module_expr_ident_name open_decl.popen_expr)
  | Pstr_module module_binding ->
      add_optional_identifier facts module_binding.pmb_name.txt;
      Option.iter
        (fun name -> facts.decision_references <- add facts.decision_references name)
        module_binding.pmb_name.txt;
      (match module_binding.pmb_expr.pmod_desc with
      | Pmod_structure nested_structure ->
          List.iter (collect_structure_item facts) nested_structure
      | _ -> ())
  | Pstr_modtype modtype_decl ->
      add_identifier facts modtype_decl.pmtd_name.txt;
      facts.decision_references <- add facts.decision_references modtype_decl.pmtd_name.txt
  | Pstr_type (_, declarations) ->
      List.iter
        (fun declaration ->
          add_identifier facts declaration.ptype_name.txt;
          facts.decision_references <- add facts.decision_references declaration.ptype_name.txt;
          (match declaration.ptype_kind with
          | Ptype_record labels ->
              List.iter
                (fun label ->
                  if label.pld_mutable = Mutable then
                    add_shared_state facts ~kind:"ocaml-mutable-field"
                      ~reference:label.pld_name.txt)
                labels
          | _ -> ()))
        declarations
  | Pstr_value (_, bindings) ->
      List.iter
        (fun binding ->
          let names = pattern_names binding.pvb_pat in
          names |> StringSet.iter (fun name ->
                     add_identifier facts name;
                     if expression_is_function binding.pvb_expr then (
                       facts.decision_surface <- add facts.decision_surface name;
                       facts.property_test_surface <- add facts.property_test_surface name;
                       facts.function_bodies <- add facts.function_bodies name;
                       facts.function_references <-
                         StringMap.add name
                           (api_references_in_expression binding.pvb_expr)
                           facts.function_references)
                     else if is_bindable_name name then
                       (* Non-function bindings (e.g. QCheck generators bound at
                          top level) join the call graph too, so reference
                          expansion is uniform across all bindings rather than
                          functions only. *)
                       facts.function_references <-
                         StringMap.add name
                           (api_references_in_expression binding.pvb_expr)
                           facts.function_references;
                     facts.decision_references <- add facts.decision_references name);
          if not (StringSet.is_empty names) && not (expression_is_function binding.pvb_expr)
          then
            facts.imperative_declarations <-
              StringSet.union facts.imperative_declarations names;
          if
            expression_contains_state_allocation binding.pvb_expr
            && (not (expression_is_function binding.pvb_expr)
               || StringSet.exists is_state_constructor_name names)
          then
            StringSet.iter
              (fun name ->
                if is_bindable_name name then
                  add_shared_state facts ~kind:"ocaml-shared-state" ~reference:name)
              names)
        bindings
  | Pstr_primitive value_description ->
      add_identifier facts value_description.pval_name.txt;
      facts.decision_surface <- add facts.decision_surface value_description.pval_name.txt;
      facts.property_test_surface <- add facts.property_test_surface value_description.pval_name.txt;
      facts.decision_references <- add facts.decision_references value_description.pval_name.txt
  | _ -> ()

let collect_signature_item facts item =
  match item.psig_desc with
  | Psig_open open_decl ->
      facts.imports <- add facts.imports (lid_last open_decl.popen_expr)
  | Psig_module module_decl ->
      add_optional_identifier facts module_decl.pmd_name.txt;
      Option.iter
        (fun name -> facts.decision_references <- add facts.decision_references name)
        module_decl.pmd_name.txt
  | Psig_modtype modtype_decl ->
      add_identifier facts modtype_decl.pmtd_name.txt;
      facts.decision_references <- add facts.decision_references modtype_decl.pmtd_name.txt
  | Psig_type (_, declarations) ->
      List.iter
        (fun declaration ->
          add_identifier facts declaration.ptype_name.txt;
          facts.decision_references <- add facts.decision_references declaration.ptype_name.txt;
          (match declaration.ptype_kind with
          | Ptype_record labels ->
              List.iter
                (fun label ->
                  if label.pld_mutable = Mutable then
                    add_shared_state facts ~kind:"ocaml-mutable-field"
                      ~reference:label.pld_name.txt)
                labels
          | _ -> ()))
        declarations
  | Psig_value value_description ->
      add_identifier facts value_description.pval_name.txt;
      facts.decision_surface <- add facts.decision_surface value_description.pval_name.txt;
      facts.property_test_surface <- add facts.property_test_surface value_description.pval_name.txt;
      facts.decision_references <- add facts.decision_references value_description.pval_name.txt
  | _ -> ()

let collect_expression_facts facts expression =
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
        (match expression.pexp_desc with
        | Pexp_ident lid
        | Pexp_construct (lid, _)
        | Pexp_field (_, lid)
        | Pexp_setfield (_, lid, _) ->
            record_longident facts lid
        | Pexp_apply (called, args) ->
            (match called.pexp_desc with
            | Pexp_ident lid -> record_longident facts lid
            | _ -> ());
            if is_property_test_call called then
              let property_body = function_body_argument args in
              (* Harvest references from every argument — the callback *and* the
                 generator (and any helper they name) — expanded through the call
                 graph. A reference reachable from the generator that builds the
                 inputs, not only the assertion callback, still counts. *)
              let references =
                args
                |> List.fold_left
                     (fun acc (_label, argument) ->
                       StringSet.union acc (api_references_in_expression argument))
                     StringSet.empty
                |> (fun direct -> expanded_api_references facts direct StringSet.empty)
                |> set_to_list
              in
              let generated_inputs =
                match property_body with
                | Some body -> generated_inputs_for_property facts body
                | None -> []
              in
              let operation_sequences =
                match property_body with
                | Some body ->
                    operation_sequences_for_property facts body args generated_inputs
                | None -> []
              in
              facts.property_checks <-
                { references; generated_inputs; operation_sequences } :: facts.property_checks
        | Pexp_ifthenelse _ -> facts.control_flow <- add facts.control_flow "if"
        | Pexp_match _ -> facts.control_flow <- add facts.control_flow "match"
        | Pexp_for _ -> facts.control_flow <- add facts.control_flow "for"
        | Pexp_while _ -> facts.control_flow <- add facts.control_flow "while"
        | Pexp_sequence _ -> facts.control_flow <- add facts.control_flow "sequence"
        | Pexp_setinstvar _ | Pexp_let _ ->
            facts.imperative_declarations <- add facts.imperative_declarations "imperative"
        | _ -> ());
        Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression

(* Does this expression directly contain a *meaningful* property check — a
   QCheck2 test whose callback actually uses a generated input? (A linking
   property over [unit] that only [ignore]s a surface does not count.) *)
let expression_has_meaningful_property facts expression =
  let found = ref false in
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
          (match expression.pexp_desc with
          | Pexp_apply (called, args) when is_property_test_call called -> (
              match function_body_argument args with
              | Some body ->
                  if
                    List.exists
                      (fun (input : generated_input) -> input.uses <> [])
                      (generated_inputs_for_property facts body)
                  then found := true
              | None -> ())
          | _ -> ());
          Ast_iterator.default_iterator.expr self expression);
    }
  in
  iterator.expr iterator expression;
  !found

let collect_structure facts structure =
  List.iter (collect_structure_item facts) structure;
  let iterator =
    {
      Ast_iterator.default_iterator with
      expr =
        (fun self expression ->
          collect_expression_facts facts expression;
          Ast_iterator.default_iterator.expr self expression);
      pat =
        (fun self pattern ->
          (match pattern.ppat_desc with
          | Ppat_construct (lid, _) -> record_longident facts lid
          | _ -> ());
          Ast_iterator.default_iterator.pat self pattern);
      typ =
        (fun self core_type ->
          (match core_type.ptyp_desc with
          | Ptyp_constr (lid, _) -> record_longident facts lid
          | _ -> ());
          Ast_iterator.default_iterator.typ self core_type);
      module_expr =
        (fun self module_expr ->
          (match module_expr.pmod_desc with
          | Pmod_ident lid -> record_longident facts lid
          | _ -> ());
          Ast_iterator.default_iterator.module_expr self module_expr);
    }
  in
  iterator.structure iterator structure;
  (* Obligatory call-graph closure for property coverage. A binding that builds
     a meaningful property — even indirectly, by passing a callback to a
     higher-order test helper (e.g. [let p = totality (fun s -> Core.parse s)])
     — reaches that property through the call graph. Fold the references of
     every such binding into the meaningful checks, so coverage follows the
     graph instead of only the syntactic callback at the QCheck2.Test.make site. *)
  let producing =
    List.fold_left
      (fun acc item ->
        match item.pstr_desc with
        | Pstr_value (_, bindings) ->
            List.fold_left
              (fun acc binding ->
                if expression_has_meaningful_property facts binding.pvb_expr then
                  StringSet.fold
                    (fun name acc -> if is_bindable_name name then add acc name else acc)
                    (pattern_names binding.pvb_pat) acc
                else acc)
              acc bindings
        | _ -> acc)
      StringSet.empty structure
  in
  if not (StringSet.is_empty producing) then begin
    let extra =
      StringMap.fold
        (fun binding refs acc ->
          let expanded = expanded_api_references facts refs StringSet.empty in
          if
            StringSet.mem binding producing
            || not (StringSet.is_empty (StringSet.inter expanded producing))
          then StringSet.union acc expanded
          else acc)
        facts.function_references StringSet.empty
    in
    facts.property_checks <-
      List.map
        (fun (check : property_check) ->
          if
            List.exists
              (fun (input : generated_input) -> input.uses <> [])
              check.generated_inputs
          then
            {
              check with
              references =
                set_to_list (StringSet.union (StringSet.of_list check.references) extra);
            }
          else check)
        facts.property_checks
  end

let collect_signature facts signature =
  List.iter (collect_signature_item facts) signature;
  let iterator =
    {
      Ast_iterator.default_iterator with
      module_type =
        (fun self module_type ->
          (match module_type.pmty_desc with
          | Pmty_ident lid -> record_longident facts lid
          | _ -> ());
          Ast_iterator.default_iterator.module_type self module_type);
      typ =
        (fun self core_type ->
          (match core_type.ptyp_desc with
          | Ptyp_constr (lid, _) -> record_longident facts lid
          | _ -> ());
          Ast_iterator.default_iterator.typ self core_type);
    }
  in
  iterator.signature iterator signature

let parse_ocaml_file path source =
  let facts = empty_facts () in
  Location.input_name := path;
  let lexbuf = Lexing.from_string source in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = path };
  if Filename.check_suffix path ".mli" then
    collect_signature facts (Parse.interface lexbuf)
  else collect_structure facts (Parse.implementation lexbuf);
  facts

let fact_for_unparseable_file path source =
  let facts = empty_facts () in
  ignore (path, source);
  facts

let interface_key path =
  try Filename.chop_extension path with Invalid_argument _ -> path

let interface_exports_for_file path =
  let source = read_file path in
  let facts =
    try parse_ocaml_file path source with
    | Syntaxerr.Error _ | Lexer.Error _ -> fact_for_unparseable_file path source
  in
  { exported_values = facts.decision_surface; exported_references = facts.decision_references }

let references_test_library facts =
  let expanded_references =
    expanded_api_references facts facts.api_references StringSet.empty
  in
  StringSet.exists
    (fun name ->
      StringSet.mem name facts.imports || StringSet.mem name expanded_references)
    test_library_identifiers

let infer_test_scope ~test_scope_paths path facts =
  (* A module is in a test scope if it references a known test library or if a
     dune [(test ...)]/[(tests ...)] stanza declares it as a test module. The
     latter covers hand-rolled harnesses (exit-code / failwith / printf tallies)
     that never touch Alcotest, QCheck, etc. *)
  if references_test_library facts || StringSet.mem path test_scope_paths then
    basename_without_extension path
  else ""

let json_string_list values =
  `List (List.map (fun value -> `String value) (sorted_unique values))

let metadata_to_json metadata =
  `Assoc
    [
      ("moduleType", `String metadata.module_type);
      ("domain", `String metadata.domain);
      ("exemptReason", `String metadata.exempt_reason);
    ]

let generated_input_to_json (input : generated_input) =
  `Assoc [ ("name", `String input.name); ("uses", json_string_list input.uses) ]

let operation_sequence_to_json (sequence : operation_sequence) =
  `Assoc
    [
      ("input", `String sequence.input);
      ("operations", json_string_list sequence.operations);
      ("assertions", json_string_list sequence.assertions);
    ]

let property_check_to_json (check : property_check) =
  `Assoc
    [
      ("references", json_string_list check.references);
      ("generatedInputs", `List (List.map generated_input_to_json check.generated_inputs));
      ( "operationSequences",
        `List (List.map operation_sequence_to_json check.operation_sequences) );
    ]

let shared_state_to_json (evidence : shared_state) =
  `Assoc
    [
      ("kind", `String evidence.kind);
      ("references", json_string_list evidence.references);
    ]

let interface_logic_evidence_to_json (evidence : interface_logic_evidence) =
  `Assoc
    [
      ("functionBodies", json_string_list evidence.function_bodies);
      ("constructorBodies", json_string_list evidence.constructor_bodies);
      ("derivedValueBodies", json_string_list evidence.derived_value_bodies);
      ("controlFlow", json_string_list evidence.control_flow);
      ("imperativeDeclarations", json_string_list evidence.imperative_declarations);
    ]

let file_fact_to_json fact =
  `Assoc
    [
      ("path", `String fact.path);
      ("testScope", `String fact.test_scope);
      ("metadata", metadata_to_json fact.metadata);
      ("imports", json_string_list fact.imports);
      ("identifiers", json_string_list fact.identifiers);
      ("apiReferences", json_string_list fact.api_references);
      ("decisionSurface", json_string_list fact.decision_surface);
      ("propertyTestSurface", json_string_list fact.property_test_surface);
      ("decisionProducts", json_string_list fact.decision_products);
      ("decisionReferences", json_string_list fact.decision_references);
      ("moduleName", `String fact.module_name);
      ("qualifiedReferences", json_string_list fact.qualified_references);
      ("effectfulImports", json_string_list fact.effectful_imports);
      ("effectfulIdentifiers", json_string_list fact.effectful_identifiers);
      ("sharedState", `List (List.map shared_state_to_json fact.shared_state));
      ("propertyChecks", `List (List.map property_check_to_json fact.property_checks));
      ( "interfaceLogicEvidence",
        interface_logic_evidence_to_json fact.interface_logic_evidence );
    ]

let shared_state_facts facts =
  StringMap.bindings facts.shared_state
  |> List.map (fun (kind, references) -> { kind; references = set_to_list references })

let effectful_import_list imports =
  imports |> List.filter (fun import -> StringSet.mem import effectful_imports)

let source_fact ~root:_ ~interfaces ~test_scope_paths ~typedtree_artifacts ~owner_modules path =
  let source = read_file path in
  let metadata = parse_metadata source in
  let facts =
    try parse_ocaml_file path source with
    | Syntaxerr.Error _ | Lexer.Error _ -> fact_for_unparseable_file path source
  in
  let module_name = String.capitalize_ascii (basename_without_extension path) in
  let artifact =
    match StringMap.find_opt (absolute_path path) typedtree_artifacts with
    | Some artifact -> artifact
    | None ->
        failwith (Printf.sprintf "missing typedtree artifact for %s" (absolute_path path))
  in
  let qualified_references =
    collect_typedtree_qualified_references ~current_module:module_name ~owner_modules
      artifact
  in
  let decision_surface, property_test_surface, decision_references =
    if Filename.check_suffix path ".ml" then
      match StringMap.find_opt (interface_key path) interfaces with
      | Some exports ->
          ( StringSet.inter facts.decision_surface exports.exported_values,
            StringSet.inter facts.property_test_surface exports.exported_values,
            StringSet.inter facts.decision_references exports.exported_references )
      | None -> (facts.decision_surface, facts.property_test_surface, facts.decision_references)
    else (facts.decision_surface, facts.property_test_surface, facts.decision_references)
  in
  {
    path;
    test_scope = infer_test_scope ~test_scope_paths path facts;
    module_name;
    qualified_references = set_to_list qualified_references;
    metadata;
    imports = set_to_list facts.imports;
    identifiers = set_to_list facts.identifiers;
    api_references = set_to_list facts.api_references;
    decision_surface = set_to_list decision_surface;
    property_test_surface = set_to_list property_test_surface;
    decision_products = set_to_list facts.decision_products;
    decision_references = set_to_list decision_references;
    effectful_imports = effectful_import_list (set_to_list facts.imports);
    effectful_identifiers = set_to_list facts.effectful_identifiers;
    shared_state = shared_state_facts facts;
    property_checks =
      List.rev facts.property_checks
      |> List.map (fun check ->
             if metadata.module_type = "stateTest" then check
             else { check with operation_sequences = [] });
    interface_logic_evidence =
      {
        function_bodies = set_to_list facts.function_bodies;
        constructor_bodies = set_to_list facts.constructor_bodies;
        derived_value_bodies = set_to_list facts.derived_value_bodies;
        control_flow = set_to_list facts.control_flow;
        imperative_declarations = set_to_list facts.imperative_declarations;
      };
  }

let should_skip_dir name =
  List.mem name [ ".git"; "_build"; "_opam"; ".wrangler"; "worktrees" ]

let rec collect_ocaml_files dir =
  Sys.readdir dir |> Array.to_list
  |> List.sort String.compare
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name in
         if Sys.is_directory path then
           if should_skip_dir name then [] else collect_ocaml_files path
         else if Filename.check_suffix name ".ml" || Filename.check_suffix name ".mli"
         then [ path ]
         else [])

let rec collect_artifact_files dir =
  let entries =
    try Sys.readdir dir |> Array.to_list |> List.sort String.compare with Sys_error _ -> []
  in
  List.concat_map
    (fun name ->
      let path = Filename.concat dir name in
      if (try Sys.is_directory path with Sys_error _ -> false) then collect_artifact_files path
      else if Filename.check_suffix name ".cmt" || Filename.check_suffix name ".cmti" then [ path ]
      else [])
    entries

let resolve_cmt_source_path ~source_root ~source_paths_by_basename cmt =
  let source_path path =
    if Filename.check_suffix path ".pp.ml" then
      Filename.chop_suffix path ".pp.ml" ^ ".ml"
    else if Filename.check_suffix path ".pp.mli" then
      Filename.chop_suffix path ".pp.mli" ^ ".mli"
    else path
  in
  match cmt.Cmt_format.cmt_sourcefile with
  | None -> None
  | Some path ->
      let normalized_path = source_path path in
      let candidates =
        if Filename.is_relative path then
          [
            Filename.concat cmt.Cmt_format.cmt_builddir path;
            Filename.concat source_root path;
            Filename.concat source_root normalized_path;
            path;
            normalized_path;
          ]
        else [ path; normalized_path ]
      in
      match
        List.find_map
          (fun candidate ->
            let candidate = absolute_path candidate in
            if Sys.file_exists candidate then Some candidate else None)
          candidates
      with
      | Some candidate -> Some candidate
      | None -> (
          match
            StringMap.find_opt (Filename.basename normalized_path) source_paths_by_basename
          with
          | Some [ source_path ] -> Some source_path
          | _ -> None)

let load_typedtree_artifacts ~source_root source_paths =
  let source_paths =
    source_paths |> List.map absolute_path |> List.sort_uniq String.compare
  in
  let source_paths_by_basename =
    List.fold_left
      (fun acc source_path ->
        let key = Filename.basename source_path in
        let existing = Option.value (StringMap.find_opt key acc) ~default:[] in
        StringMap.add key (source_path :: existing) acc)
      StringMap.empty source_paths
  in
  let artifact_root = Filename.concat source_root "_build" in
  let artifact_paths = collect_artifact_files artifact_root in
  let visible_dirs =
    artifact_paths
    |> List.map Filename.dirname
    |> List.fold_left add StringSet.empty
    |> set_to_list
  in
  Load_path.init ~auto_include:Load_path.no_auto_include ~visible:visible_dirs ~hidden:[];
  let artifacts =
    artifact_paths
    |> List.filter_map (fun artifact_path ->
           let cmt = Cmt_format.read_cmt artifact_path in
           match resolve_cmt_source_path ~source_root ~source_paths_by_basename cmt with
           | None -> None
           | Some source_path ->
               Some
                 {
                   artifact_path;
                   source_path;
                   load_path_visible = cmt.Cmt_format.cmt_loadpath.visible;
                   load_path_hidden = cmt.Cmt_format.cmt_loadpath.hidden;
                 })
  in
  let visible_from_cmts =
    artifacts
    |> List.concat_map (fun artifact -> artifact.load_path_visible)
    |> List.fold_left add StringSet.empty
    |> set_to_list
  in
  let hidden_from_cmts =
    artifacts
    |> List.concat_map (fun artifact -> artifact.load_path_hidden)
    |> List.fold_left add StringSet.empty
    |> set_to_list
  in
  Load_path.init ~auto_include:Load_path.no_auto_include
    ~visible:(sorted_unique (visible_dirs @ visible_from_cmts))
    ~hidden:hidden_from_cmts;
  let artifacts_by_source =
    List.fold_left
      (fun acc artifact -> StringMap.add artifact.source_path artifact acc)
      StringMap.empty artifacts
  in
  let missing =
    source_paths
    |> List.map absolute_path
    |> List.filter (fun path -> not (StringMap.mem path artifacts_by_source))
  in
  if missing <> [] then
    failwith
      (Printf.sprintf
         "missing typedtree artifacts for: %s; configure Dune with (bin_annot true) and build @check before running Archlint"
         (String.concat ", " missing));
  artifacts_by_source

(* Minimal S-expression reader, just enough to find dune stanzas. dune files
   are S-expressions; we tolerate comments and strings and ignore everything we
   do not recognise. *)
type sexp = Atom of string | Node of sexp list

let parse_sexps text =
  let length = String.length text in
  let pos = ref 0 in
  let peek () = if !pos < length then Some text.[!pos] else None in
  let advance () = incr pos in
  let rec skip_ws () =
    match peek () with
    | Some (' ' | '\t' | '\n' | '\r') ->
        advance ();
        skip_ws ()
    | Some ';' ->
        while match peek () with Some c -> c <> '\n' | None -> false do
          advance ()
        done;
        skip_ws ()
    | _ -> ()
  in
  let read_quoted () =
    advance ();
    let buf = Buffer.create 16 in
    let rec loop () =
      match peek () with
      | None | Some '"' -> advance ()
      | Some '\\' ->
          advance ();
          (match peek () with
          | Some c ->
              Buffer.add_char buf c;
              advance ()
          | None -> ());
          loop ()
      | Some c ->
          Buffer.add_char buf c;
          advance ();
          loop ()
    in
    loop ();
    Buffer.contents buf
  in
  let is_atom_char c =
    not
      (c = '(' || c = ')' || c = '"' || c = ';' || c = ' ' || c = '\t'
     || c = '\n' || c = '\r')
  in
  let read_atom () =
    let buf = Buffer.create 16 in
    let rec loop () =
      match peek () with
      | Some c when is_atom_char c ->
          Buffer.add_char buf c;
          advance ();
          loop ()
      | _ -> ()
    in
    loop ();
    Buffer.contents buf
  in
  let rec read_one () =
    skip_ws ();
    match peek () with
    | None -> None
    | Some ')' ->
        advance ();
        None
    | Some '(' ->
        advance ();
        Some (Node (read_seq ()))
    | Some '"' -> Some (Atom (read_quoted ()))
    | Some _ -> Some (Atom (read_atom ()))
  and read_seq () =
    match read_one () with Some item -> item :: read_seq () | None -> []
  in
  read_seq ()

(* Module names declared by a dune [(test ...)]/[(tests ...)] stanza, read from
   its [name]/[names]/[modules] fields. Set operators like [:standard] and [\]
   in a [modules] field are non-atom or non-module tokens and are skipped. *)
let test_modules_of_sexp = function
  | Node (Atom head :: fields) when head = "test" || head = "tests" ->
      List.concat_map
        (function
          | Node (Atom field :: args)
            when field = "name" || field = "names" || field = "modules" ->
              List.filter_map (function Atom a -> Some a | _ -> None) args
          | _ -> [])
        fields
  | _ -> []

(* Absolute paths of [.ml] files declared as test modules by dune stanzas under
   [dir]. Mirrors collect_ocaml_files so the produced paths match exactly. *)
let rec collect_test_scope_paths dir =
  let entries =
    try Sys.readdir dir |> Array.to_list |> List.sort String.compare
    with Sys_error _ -> []
  in
  let here =
    if List.mem "dune" entries then
      let modules =
        try
          parse_sexps (read_file (Filename.concat dir "dune"))
          |> List.concat_map test_modules_of_sexp
        with _ -> []
      in
      List.concat_map
        (fun m ->
          (* dune module names map case-insensitively to file names; emit both
             the verbatim and uncapitalised forms and let set membership pick
             the one that matches a real file. *)
          [
            Filename.concat dir (m ^ ".ml");
            Filename.concat dir (String.uncapitalize_ascii m ^ ".ml");
          ])
        modules
    else []
  in
  let nested =
    List.concat_map
      (fun name ->
        let path = Filename.concat dir name in
        if (try Sys.is_directory path with Sys_error _ -> false) then
          if should_skip_dir name then [] else collect_test_scope_paths path
        else [])
      entries
  in
  here @ nested

let repo_root = ref "."
let ocaml_root = ref "."

let args =
  [
    ("--repo-root", Arg.Set_string repo_root, "Repository root");
    ("--ocaml-root", Arg.Set_string ocaml_root, "OCaml source root relative to repository root");
  ]

let () =
  Arg.parse args (fun value -> raise (Arg.Bad ("unexpected argument: " ^ value))) "archlint_ocaml_adapter";
  let root =
    if Filename.is_relative !repo_root then Filename.concat (Sys.getcwd ()) !repo_root
    else !repo_root
  in
  let source_root =
    if Filename.is_relative !ocaml_root then Filename.concat root !ocaml_root
    else !ocaml_root
  in
  let paths = collect_ocaml_files source_root in
  let typedtree_artifacts = load_typedtree_artifacts ~source_root paths in
  let owner_modules =
    paths
    |> List.map (fun path -> String.capitalize_ascii (basename_without_extension path))
    |> List.fold_left add StringSet.empty
  in
  let test_scope_paths = StringSet.of_list (collect_test_scope_paths source_root) in
  let interfaces =
    List.fold_left
      (fun acc path ->
        if Filename.check_suffix path ".mli" then
          StringMap.add (interface_key path) (interface_exports_for_file path) acc
        else acc)
      StringMap.empty paths
  in
  let files =
    paths
    |> List.map
         (source_fact ~root ~interfaces ~test_scope_paths ~typedtree_artifacts
            ~owner_modules)
  in
  let json = `Assoc [ ("files", `List (List.map file_fact_to_json files)) ] in
  Yojson.Safe.pretty_to_channel stdout json;
  output_char stdout '\n'
