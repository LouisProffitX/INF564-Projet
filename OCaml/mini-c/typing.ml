open Format
open Ttree

(* utiliser cette exception pour signaler une erreur de typage *)
exception Error of string

type environment = {
  vars: (string, typ) Hashtbl.t;
  structs: (string, structure) Hashtbl.t;
  funs: (string, decl_fun) Hashtbl.t;
  returnType: typ
}

let string_of_type = function
  | Tint       -> "int"
  | Tstructp x -> "struct " ^ x.str_name ^ "*"
  | Tvoidstar  -> "void*"
  | Ttypenull  -> "typenull"


let type_equiv t s =
  match (t, s) with
    | (a, b) when b = a       -> true
    | (Ttypenull, Tint)       -> true
    | (Ttypenull, Tstructp _) -> true
    | (Tvoidstar, Tstructp _) -> true
    | (Tint, Ttypenull)       -> true
    | (Tstructp _, Ttypenull) -> true
    | (Tstructp _, Tvoidstar) -> true
    | (Tstructp i1, Tstructp i2) -> String.equal i1.str_name i2.str_name
    | _                       -> false

let rec type_expr env = function
  | Ptree.Econst 0l ->
  {
    expr_node = Econst 0l;
    expr_typ = Ttypenull;
  }
  | Ptree.Econst n  ->
  {
    expr_node = Econst n;
    expr_typ = Ttypenull;
   }
  | Ptree.Eright (Ptree.Lident x) ->
    (try {expr_node = Eaccess_local x.id; expr_typ = Hashtbl.find env.vars x.id}
     with Not_found -> raise (Error ("the variable " ^ x.id ^ " is not assigned")))
  | Ptree.Eright (Ptree.Larrow (e, x)) ->
    let texpr = type_expr env e.expr_node in
    (match texpr.expr_typ with
      | Tstructp str -> (
        try let structure = Hashtbl.find env.structs str.str_name
            in let f = Hashtbl.find structure.str_fields x.id
               in {expr_node = Eaccess_field (texpr, f);
                   expr_typ = f.field_typ}
       with Not_found -> raise (Error ("structure "^str.str_name^" not defined")))
      | _            -> raise (Error "you are trying to access a field of something that is not a structure")
)
  | Ptree.Eassign (Ptree.Lident x, e) ->
    let texpr = type_expr env e.expr_node in
    (try let ty_left = Hashtbl.find env.vars x.id in
       if type_equiv ty_left texpr.expr_typ
       then {expr_node = Eassign_local (x.id, texpr); expr_typ = texpr.expr_typ}
       else raise (Error ("Assigning " ^ x.id ^ " of type "^(string_of_type ty_left)^" with type "^(string_of_type texpr.expr_typ)))
     with Not_found -> raise (Error ("the variable " ^ x.id ^ " is not declared (assignement)"))
     )
  | Ptree.Eassign (Ptree.Larrow (e1, x), e2) ->
    let texpr1 = type_expr env e1.expr_node and texpr2 = type_expr env e2.expr_node in
    (match texpr1.expr_typ with
      | Tstructp str -> (
        try let structure = Hashtbl.find env.structs str.str_name
            in let f = Hashtbl.find structure.str_fields x.id
               in if type_equiv f.field_typ texpr2.expr_typ
                  then {expr_node = Eassign_field (texpr1, f, texpr2); expr_typ = f.field_typ}
                  else raise (Error ("Assigning "^x.id^" of type "^(string_of_type f.field_typ)^" with type "^(string_of_type texpr2.expr_typ)))
        with Not_found -> raise (Error "you are trying to assign a field of a structure that is not defined"))
      | _            -> raise (Error "you are trying to assign a field of something that is not a structure")
)
  | Ptree.Eunop (Unot,e) -> let expr = type_expr env e.expr_node in {expr_node=Eunop(Unot, expr);expr_typ=Tint}
  | Ptree.Eunop (Uminus,e) -> let expr = type_expr env e.expr_node in
    if (type_equiv expr.expr_typ Tint)
    then {expr_node=Eunop(Uminus, expr);expr_typ=Tint}
    else raise (Error "Negation of a non integer variable not defined")
    | Ptree.Ebinop (b,e1,e2) ->
    let ne1 = type_expr env e1.expr_node in
    let ne2 = type_expr env e2.expr_node in
    begin match b with
    | Beq
    | Bneq
    | Blt
    | Ble
    | Bgt
    | Bge->
      if (type_equiv ne1.expr_typ ne2.expr_typ)
      then {expr_node=Ebinop(b, ne1, ne2);expr_typ=Tint}
      else raise (Error "Incompatible types for binop")
     | Badd
     | Bsub
     | Bmul
     | Bdiv ->
      if ((type_equiv ne1.expr_typ Tint) && (type_equiv ne2.expr_typ Tint))
      then {expr_node=Ebinop(b, ne1, ne2);expr_typ=Tint}
      else raise (Error "Incompatible types for binop")
     | Band
     | Bor ->
     {expr_node=Ebinop(b, ne1, ne2);expr_typ=Tint}
    end
  | Ptree.Ecall (i,el) ->
  (try (let mfun = Hashtbl.find env.funs i.id in
    (try let expr_list = List.map2 (
        fun (expr:Ptree.expr) (t,i) -> let mexpr = type_expr env expr.expr_node in
        if (type_equiv mexpr.expr_typ t)
        then mexpr else raise (Error "non matching types")
       ) el mfun.fun_formals in
    {expr_node=Ecall(i.id, expr_list);expr_typ=mfun.fun_typ}
   with Invalid_argument e -> raise (Error "wrong number of arguments")))
   with Not_found -> raise (Error ("function "^i.id^" not defined")))
  | Ptree.Esizeof i ->
  try let structure = Hashtbl.find env.structs i.id in {expr_node=Esizeof(structure); expr_typ=Tint}
  with Not_found -> raise (Error ("structure "^i.id^" not defined"))
  | _         -> assert false

and type_type env = function
  | Ptree.Tint -> Tint
  | Ptree.Tstructp ident -> try Tstructp (Hashtbl.find env.structs ident.id) with Not_found -> raise (Error ("type_type failed with " ^ ident.id))


and type_stmt env (s: Ptree.stmt) =
  match s.stmt_node with
  | Ptree.Sskip           -> Sskip
  | Ptree.Sexpr e         -> Sexpr (type_expr env e.expr_node)
  | Ptree.Sblock (dl, sl) -> Sblock(type_block env (dl,sl))
  | Ptree.Sreturn e       ->
    let expr = type_expr env e.expr_node in
    if (type_equiv (expr.expr_typ) (env.returnType)) then Sreturn(expr) else raise (Error("Wrong return type"))
  | Ptree.Sif (e,s1,s2) -> Sif(type_expr env e.expr_node, type_stmt env s1, type_stmt env s2)
  | Ptree.Swhile (e,s) -> Swhile(type_expr env e.expr_node, type_stmt env s)


and type_block env ((dl, sl):(Ptree.decl_var list * Ptree.stmt list)) =
    let new_vars = Hashtbl.create 15 in
    List.iter (fun ((tt,i):(Ptree.typ*Ptree.ident)) ->
    if (Hashtbl.mem new_vars i.id) then raise (Error ("variable "^i.id^" defined twice in the block")) else Hashtbl.add new_vars i.id (type_type env tt)
    ) dl;
    Hashtbl.iter (Hashtbl.add env.vars) new_vars;
    let stmts = List.map (type_stmt env) sl in
    Hashtbl.iter (fun i t -> Hashtbl.remove env.vars i) new_vars;
    let decls = List.map (fun ((t,i):(Ptree.typ*Ptree.ident)) -> (Hashtbl.find new_vars i.id,i.id)) dl in
    (decls, stmts)

let program (p: Ptree.file) =
  let rec aux env = function
    | [] -> []
    | (Ptree.Dstruct (id, l)) :: q ->
        if (Hashtbl.mem env.structs id.id) then raise (Error ("struct " ^ id.id ^ " was already declared"));
        Hashtbl.add env.structs id.id {str_name = id.id; str_fields = Hashtbl.create 1};
        (let new_fields = Hashtbl.create 15 in
        (let rec fill_struct h (li: Ptree.decl_var list) =
          match li with
            | []                -> ()
            | (ty, id_var) :: q ->
            if (Hashtbl.mem h id_var.id) then raise (Error ("Struct "^id.id^" contains two fields named "^" id_var"))
            else (Hashtbl.add h id_var.id)
            {
                field_name = id_var.id;
                field_typ = type_type env ty
            };
            fill_struct h q
         in
         fill_struct new_fields l;
         let new_struct = {
           str_name = id.id;
           str_fields = new_fields
         } in
         Hashtbl.remove env.structs id.id;
         Hashtbl.add env.structs id.id new_struct;
         aux env q))
    | (Ptree.Dfun d) :: q -> (
        let fun_name = d.fun_name.id in
        (if (Hashtbl.mem env.funs fun_name) then raise (Error ("function named "^fun_name^" defined twice")));
        let fun_typ = type_type env d.fun_typ in
        let fun_formals = List.map
        (
            fun ((pt,i):(Ptree.typ*Ptree.ident)) -> let tt = type_type env pt in
            (if (Hashtbl.mem env.vars i.id) then raise (Error ("function "^fun_name^" has two arguments named "^i.id^""))
            else Hashtbl.add env.vars i.id tt);
            (tt,i.id)
        ) d.fun_formals in
        Hashtbl.add env.funs fun_name {fun_typ=fun_typ;fun_name=fun_name;fun_formals=fun_formals;fun_body=([],[])};
        let fun_body = type_block env d.fun_body in
        let ttree_dfun = {
          fun_typ = fun_typ;
          fun_name = fun_name;
          fun_formals = fun_formals;
          fun_body = fun_body;
        } in
        Hashtbl.replace env.funs fun_name ttree_dfun;
        (List.iter (fun (t,i) -> Hashtbl.remove env.vars i) fun_formals);
        ttree_dfun :: (aux env q)
      )
   in
   let env = {
     vars = Hashtbl.create 15;
     structs = Hashtbl.create 10;
     funs = Hashtbl.create 10;
     returnType = Ttypenull
   } in
   Hashtbl.add env.funs "putchar"
   {
    fun_typ = Tint;
    fun_name = "putchar";
    fun_formals = [(Tint, "c")];
    fun_body = ([],[Sskip]);
   };
   Hashtbl.add env.funs "sbrk"
      {
       fun_typ = Tvoidstar;
       fun_name = "sbrk";
       fun_formals = [(Tint, "n")];
       fun_body = ([],[Sskip]);
      };
   let funs = aux env p in
   (try let main_fun = Hashtbl.find env.funs "main" in
   if ((List.length main_fun.fun_formals != 0) || not(type_equiv main_fun.fun_typ Tint)) then raise (Error "incorrect main function")
   with Not_found -> raise (Error "main function missing"));
   {
     funs = funs;
   }



