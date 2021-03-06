(** A mini-ML
    @author Stuart M. Shieber

    This module implements a small untyped ML-like language under
    various operational semantics.
 *)

open Expr ;;
  
(* Exception for evaluator runtime generated by a runtime error *)
exception EvalError of string ;;
(* Exception for evaluator runtime generated by an explicit "raise" construct *)
exception EvalException ;;

type scope = 
  | S
  | D 
  | L
;;

module type Env_type = sig
    type env
    type value =
      | Val of expr
      | Closure of (expr * env)
    val create : unit -> env
    val close : expr -> env -> value
    val lookup : env -> varid -> value
    val extend : env -> varid -> value ref -> env
    val env_to_string : env -> string
    val value_to_string : ?printenvp:bool -> value -> string
  end

module Env : Env_type =
  struct
    type env = (varid * value ref) list
     and value =
       | Val of expr
       | Closure of (expr * env)

    exception EnvUnbound

    (* Creates an empty environment *)
    let create () : env = [] ;;

    (* Creates a closure from an expression and the environment it's
       defined in *)
    let close (exp: expr) (env: env) : value = 
      Closure (exp, env) ;;

    (* Looks up the value of a variable in the environment *)
    let rec lookup (env: env) (varname: varid) : value =
      match env with
      | (v, r)::t -> if v = varname then !r else lookup t varname 
      | [] -> Val (Unassigned) ;;

    (* Returns a new environment just like env except that it maps the
       variable varname to loc *)
    let rec extend (env: env) (varname: varid) (loc: value ref) : env =
      match env with 
      | (v, r)::t -> if v = varname then ((v, loc)::t)
        else (v, r)::(extend t varname loc)
      | [] -> [(varname, loc)] ;;

    (* Returns a printable string representation of an environment *)
    let rec env_to_string (env: env) : string =
      match env with 
      | (v, r)::[] -> "(" ^ v ^ ", " ^ (value_to_string !r) ^ ")"
      | (v, r)::t -> "(" ^ v ^ ", " ^ (value_to_string !r) ^ "), " 
          ^ (env_to_string t)
      | [] -> ""

    (* Returns a printable string representation of a value; the flag
       printenvp determines whether to include the environment in the
       string representation when called on a closure *)
    and value_to_string ?(printenvp : bool = true) (v: value) : string =
      match v with 
      | Val exp -> exp_to_string exp
      | Closure (exp, env) -> if printenvp 
        then "(" ^ exp_to_string exp ^ ", " ^ env_to_string env ^ ")"
        else exp_to_string exp ;;
  end
;;

let eval_t exp _env = Env.Val exp ;;

let unopeval (op : varid) (v : Env.value) = 
  match v with 
  | Env.Closure (_, _) -> raise (EvalError "unopeval recieved closure")
  | Env.Val e -> match e with 
    | Num i -> (match op with
      | "~" -> Num (-i)
      | _ -> raise (EvalError ("invalid unary operator on ints " ^ op)))
    | _ -> raise (EvalError ("invalid unary operand to " ^ op)) 
;;

let binopeval (op : varid) (v1 : Env.value) (v2 : Env.value) = 
  match v1, v2 with 
  | Env.Val e1, Env.Val e2 ->
    (match e1, e2 with 
    | Num i1, Num i2 -> (match op with
      | "+" -> Num (i1 + i2) 
      | "-" -> Num (i1 - i2) 
      | "*" -> Num (i1 * i2) 
      | "=" -> Bool (i1 = i2)  
      | "<" -> Bool (i1 < i2) 
      | _ -> raise (EvalError ("invalid binary operator " ^ op)))
    | _ -> raise (EvalError ("invalid operands to " ^ op)))
  | _, _ -> raise (EvalError "binopeval did not receive values")
;;

let eval_s (exp : expr) (_env : Env.env) : Env.value = 
  let rec eval (ex : expr) : expr =
    match ex with
    | Var v -> raise (EvalError ("unbound variable " ^ v))      
    | Num i -> Num i                 
    | Bool b -> Bool b               
    | Unop (v, e) -> eval (unopeval v (Env.Val (eval e)))
    | Binop (v, e1, e2) -> eval (binopeval v (Env.Val (eval e1)) 
        (Env.Val (eval e2)))  
    | Conditional (e1, e2, e3) -> (match eval e1 with 
      | Bool b -> if b then eval e2 else eval e3
      | _ -> raise (EvalError "invalid conditional expression"))
    | Fun (v, e) -> Fun (v, e)         
    | Let (v, e1, e2) -> eval (subst v (eval e1) e2)     
    | Letrec (v, e1, e2) -> eval (subst v (subst v (Letrec (v, e1, Var v)) 
        e1) e2) 
    | Raise -> raise EvalException                           
    | Unassigned -> raise (EvalError "explicitly unassigned variable")                      
    | App (e1, e2) -> match (eval e1) with
      | Fun (v, e) -> eval (subst v (eval e2) e)
      | _ -> raise (EvalError "only a function can be applied")
  in Env.Val (eval exp) 
;;

let eval_method (exp : expr) (env : Env.env) (s : scope) : Env.value = 
  let rec eval (exp : expr) (env : Env.env) =
    match exp with
    | Var v -> (match Env.lookup env v with 
      | Env.Val e -> eval e env
      | Env.Closure (e, en) -> (match s with 
        | L -> eval e en 
        | D | S -> raise (EvalError "can't happen")))
    | Num i -> Env.Val (Num i)       
    | Bool b -> Env.Val (Bool b)              
    | Unop (v, e) -> eval (unopeval v (eval e env)) env
    | Binop (v, e1, e2) -> eval (binopeval v (eval e1 env) (eval e2 env)) env
    | Conditional (e1, e2, e3) -> (match eval e1 env with
      | Env.Val (Bool b) -> if b then eval e2 env else eval e3 env
      | _ -> raise (EvalError "invalid conditional expression"))
    | Fun (v, e) -> (match s with 
      | L -> Env.close (Fun (v, e)) env 
      | D -> Env.Val (Fun (v, e))
      | S -> raise (EvalError "can't happen"))    
    | Let (v, e1, e2) -> eval e2 (Env.extend env v (ref (eval e1 env)))
    | Letrec (v, e1, e2) -> (match s with
      | L -> let buf = ref (Env.Val Unassigned) in
          let e1' = ref (eval e1 (Env.extend env v buf)) in
            buf := !e1';
            eval e2 (Env.extend env v e1')
      | D | S -> eval e2 (Env.extend env v (ref (eval e1 (Env.extend env v
        (ref (Env.Val Unassigned)))))))
    | Raise -> raise EvalException                         
    | Unassigned -> raise (EvalError "unassigned variable")                
    | App (e1, e2) -> (match s with 
      | L -> (match (eval e1 env) with
        | Env.Closure (Fun (v, e), en) ->
          eval e (Env.extend en v (ref (eval e2 env)))
        | _ -> raise (EvalError "only a function can be applied"))
      | D -> (match (eval e1 env) with
        | Env.Val (Fun (v, e)) -> 
          eval e (Env.extend env v (ref (eval e2 env)))
        | _ -> raise (EvalError "only a function can be applied"))
      | S -> raise (EvalError "can't happen"))
  in eval exp env
;;

let eval_d (expr : expr) (env : Env.env) : Env.value =
  eval_method expr env D
;;

let eval_l (expr : expr) (env : Env.env) : Env.value =
  eval_method expr env L
;;

let evaluate = eval_d ;;
