(** Canonical qualified references derived from compiler [Path.t] values.

    Owners are exact compilation-unit names read from source-backed typedtree
    artifacts. Dune's default wrapping compiles source module [Decision] as an
    internal unit such as [Wrapper__Decision]. Both that internal path and the
    public alias path [Wrapper.Decision] canonicalize to [Decision], but only
    when [Wrapper__Decision] is present in the owner index. *)

type owner_index

val owner_index : (string * string) list -> owner_index
(** [owner_index owners] indexes [(compilation_unit, source_module)] pairs.
    Ambiguous compilation-unit names are ignored rather than guessed. *)

val canonicalize :
  owner_index -> current_module:string -> Path.t -> string option
(** [canonicalize owners ~current_module path] returns the evaluator's
    [Module.symbol] form for a path owned by another source module. Paths
    rooted at local identifiers, containing functor applications,
    self-references, and paths whose compilation unit is not in [owners]
    return [None]. *)
