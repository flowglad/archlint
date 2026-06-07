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
type property_check = {
  references : string list;
  interleaving : bool;
  generated_inputs : generated_input list;
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

type facts = {
  mutable imports : StringSet.t;
  mutable identifiers : StringSet.t;
  mutable api_references : StringSet.t;
  mutable decision_surface : StringSet.t;
  mutable property_test_surface : StringSet.t;
  mutable decision_products : StringSet.t;
  mutable decision_references : StringSet.t;
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

let rec expression_contains_interleaving_generator expression =
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

let generated_input_uses facts body name =
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
         |> List.map (fun name -> { name; uses = generated_input_uses facts body name }))

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
                           facts.function_references);
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
              let references =
                match property_body with
                | Some body ->
                    expanded_api_references facts
                      (api_references_in_expression body)
                      StringSet.empty
                    |> set_to_list
                | None -> []
              in
              let generated_inputs =
                match property_body with
                | Some body -> generated_inputs_for_property facts body
                | None -> []
              in
              let interleaving =
                List.exists
                  (fun (_label, argument) -> expression_contains_interleaving_generator argument)
                  args
              in
              facts.property_checks <-
                { references; interleaving; generated_inputs } :: facts.property_checks
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
  iterator.structure iterator structure

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

let infer_test_scope path facts =
  if references_test_library facts then
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

let property_check_to_json (check : property_check) =
  `Assoc
    [
      ("references", json_string_list check.references);
      ("interleaving", `Bool check.interleaving);
      ("generatedInputs", `List (List.map generated_input_to_json check.generated_inputs));
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

let source_fact ~root:_ ~interfaces path =
  let source = read_file path in
  let metadata = parse_metadata source in
  let facts =
    try parse_ocaml_file path source with
    | Syntaxerr.Error _ | Lexer.Error _ -> fact_for_unparseable_file path source
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
    test_scope = infer_test_scope path facts;
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
             else { check with interleaving = false });
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
  let interfaces =
    List.fold_left
      (fun acc path ->
        if Filename.check_suffix path ".mli" then
          StringMap.add (interface_key path) (interface_exports_for_file path) acc
        else acc)
      StringMap.empty paths
  in
  let files = paths |> List.map (source_fact ~root ~interfaces) in
  let json = `Assoc [ ("files", `List (List.map file_fact_to_json files)) ] in
  Yojson.Safe.pretty_to_channel stdout json;
  output_char stdout '\n'
