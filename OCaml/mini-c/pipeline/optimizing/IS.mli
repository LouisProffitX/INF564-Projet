
(** Arbres issus de l'optimisation *)

type ident = string

type unop = Ptree.unop

type binop = Ptree.binop

and expr =
  | Econst of int32
  | Eaccess_local of ident
  | Eassign_local of ident * expr
  | Eaccess_shift of expr * int
  | Eassign_shift of expr * int * expr
  | Eunop of unop * expr
  | Ebinop of binop * expr * expr
  | Ecall of ident * expr list

(** Instruction *)
type stmt =
  | Sskip
  | Sexpr of expr
  | Sifelse of expr * stmt * stmt
  | Sif of expr * stmt
  | Swhile of expr * stmt
  | Sblock of block
  | Sreturn of expr

and block = stmt list (* int is the index of the block *)

and decl_fun = {
  fun_name   : ident;
  fun_formals: ident list;
  fun_locals : ident list;
  fun_body   : block
}

type file = {
  funs: decl_fun list;
}


