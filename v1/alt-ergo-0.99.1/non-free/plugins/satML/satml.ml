(******************************************************************************)
(*                               OCamlPro                                     *)
(*                                                                            *)
(* Copyright 2013-2014 OCamlPro                                               *)
(* All rights reserved. See accompanying files for the terms under            *)
(* which this file is distributed. In doubt, contact us at                    *)
(* contact@ocamlpro.com (http://www.ocamlpro.com/)                            *)
(*                                                                            *)
(******************************************************************************)

(*==============================================================================

  Acknowledgement: some parts of this file are taken from the release 0.3 of
  Alt-Ergo-Zero (extracted from Cubicle), which is under the terms of the
  Apache Software License version 2.0 (see Copyright below)

(**************************************************************************)
(*                                                                        *)
(*                                  Cubicle                               *)
(*             Combining model checking algorithms and SMT solvers        *)
(*                                                                        *)
(*                  Sylvain Conchon and Alain Mebsout                     *)
(*                  Universite Paris-Sud 11                               *)
(*                                                                        *)
(*  Copyright 2011. This file is distributed under the terms of the       *)
(*  Apache Software License version 2.0                                   *)
(*                                                                        *)
(**************************************************************************)

==============================================================================*)

open Format
open Options

module F = Formula
module MF = F.Map
module SF = F.Set
module A = Literal.LT
module T = Term
module Hs = Hstring

module Vec : sig
  type 'a t = { mutable dummy: 'a; mutable data : 'a array; mutable sz : int }
  val make : int -> 'a -> 'a t
  val init : int -> (int -> 'a) -> 'a -> 'a t
  val from_array : 'a array -> int -> 'a -> 'a t
  val from_list : 'a list -> int -> 'a -> 'a t
  val clear : 'a t -> unit
  val shrink : 'a t -> int -> unit
  val pop : 'a t -> unit
  val size : 'a t -> int
  val is_empty : 'a t -> bool
  val grow_to : 'a t -> int -> unit
  val grow_to_double_size : 'a t -> unit
  val grow_to_by_double : 'a t -> int -> unit
  val is_full : 'a t -> bool
  val push : 'a t -> 'a -> unit
  val push_none : 'a t -> unit
  val last : 'a t -> 'a
  val get : 'a t -> int -> 'a
  val set : 'a t -> int -> 'a -> unit
  val set_size : 'a t -> int -> unit
  val copy : 'a t -> 'a t
  val move_to : 'a t -> 'a t -> unit
  val remove : 'a t -> 'a -> unit
  val fast_remove : 'a t -> 'a -> unit
  val sort : 'a t -> ('a -> 'a -> int) -> unit
end = struct
  type 'a t = { mutable dummy: 'a; mutable data : 'a array; mutable sz : int }
      
  let make capa d = {data = Array.make capa d; sz = 0; dummy = d}

  let init capa f d = 
    {data = Array.init capa (fun i -> f i); sz = capa; dummy = d}

  let from_array data sz d = {data = data; sz = sz; dummy = d}

  let from_list l sz d = 
    let l = ref l in
    let f_init i = match !l with [] -> assert false | e::r -> l := r; e in
    {data = Array.init sz f_init; sz = sz; dummy = d}

  let clear s = s.sz <- 0
    
  let shrink t i = assert (i >= 0 && i<=t.sz); t.sz <- t.sz - i

  let pop t = assert (t.sz >=1); t.sz <- t.sz - 1

  let size t = t.sz

  let is_empty t = t.sz = 0

  let grow_to t new_capa = 
    let data = t.data in
    let capa = Array.length data in
    t.data <- 
      Array.init new_capa
      (fun i -> if i < capa then data.(i) else t.dummy)

  let grow_to_double_size t = grow_to t (2* Array.length t.data)

  let rec grow_to_by_double t new_capa = 
    let data = t.data in
    let capa = ref (Array.length data + 1) in
    while !capa < new_capa do capa := 2 * !capa done;
    grow_to t !capa


  let is_full t = Array.length t.data = t.sz

  let push t e = 
  (*Format.eprintf "push; sz = %d et capa=%d@." t.sz (Array.length t.data);*)
    if is_full t then grow_to_double_size t;
    t.data.(t.sz) <- e;
    t.sz <- t.sz + 1

  let push_none t = 
    if is_full t then grow_to_double_size t;
    t.data.(t.sz) <- t.dummy;
    t.sz <- t.sz + 1
      
  let last t = 
    let e = t.data.(t.sz - 1) in
    assert (not (e == t.dummy));
    e

  let get t i = 
    assert (i < t.sz);
    let e = t.data.(i) in
    if e == t.dummy then raise Not_found
    else e
      
  let set t i v = 
    t.data.(i) <- v;
    t.sz <- max t.sz (i + 1)

  let set_size t sz = t.sz <- sz

  let copy t = 
    let data = t.data in
    let len = Array.length data in
    let data = Array.init len (fun i -> data.(i)) in
    { data=data; sz=t.sz; dummy = t.dummy }

  let move_to t t' =
    let data = t.data in
    let len = Array.length data in
    let data = Array.init len (fun i -> data.(i)) in
    t'.data <- data;
    t'.sz <- t.sz


  let remove t e = 
    let j = ref 0 in
    while (!j < t.sz && not (t.data.(!j) == e)) do incr j done;
    assert (!j < t.sz);
    for i = !j to t.sz - 2 do t.data.(i) <- t.data.(i+1) done;
    pop t
      

  let fast_remove t e = 
    let j = ref 0 in
    while (!j < t.sz && not (t.data.(!j) == e)) do incr j done;
    assert (!j < t.sz);
    t.data.(!j) <- last t;
    pop t


  let sort t f = 
    let sub_arr = Array.sub t.data 0 t.sz in
    Array.fast_sort f sub_arr;
    t.data <- sub_arr

(*
  template<class V, class T>
  static inline void remove(V& ts, const T& t)
  {
  int j = 0;
  for (; j < ts.size() && ts[j] != t; j++);
  assert(j < ts.size());
  ts[j] = ts.last();
  ts.pop();
  }
  #endif

  template<class V, class T>
  static inline bool find(V& ts, const T& t)
  {
  int j = 0;
  for (; j < ts.size() && ts[j] != t; j++);
  return j < ts.size();
  }

  #endif
*)
end

module Iheap : sig

  type t

  val init : int -> t
  val in_heap : t -> int -> bool
  val decrease : (int -> int -> bool) -> t -> int -> unit
(*val increase : (int -> int -> bool) -> t -> int -> unit*)
  val size : t -> int
  val is_empty : t -> bool
  val insert : (int -> int -> bool) -> t -> int -> unit
  val grow_to_by_double: t -> int -> unit
(*val update : (int -> int -> bool) -> t -> int -> unit*)
  val remove_min : (int -> int -> bool) -> t -> int
  val filter : t -> (int -> bool) -> (int -> int -> bool) -> unit

end = struct
  type t = {heap : int Vec.t; indices : int Vec.t }
      
  let dummy = -100

  let init sz = 
    { heap    =  Vec.init sz (fun i -> i) dummy;
      indices =  Vec.init sz (fun i -> i) dummy}
      
  let left i   = (i lsl 1) + 1 (* i*2 + 1 *)
  let right i  = (i + 1) lsl 1 (* (i+1)*2 *)
  let parent i = (i - 1) asr 1 (* (i-1) / 2 *)

(*
  let rec heap_property cmp ({heap=heap} as s) i = 
  i >= (Vec.size heap)  || 
  ((i = 0 || not(cmp (Vec. get heap i) (Vec.get heap (parent i))))
  && heap_property cmp s (left i) && heap_property cmp s (right i))
  
  let heap_property cmp s = heap_property cmp s 1
*)
    
  let percolate_up cmp {heap=heap;indices=indices} i = 
    let x = Vec.get heap i in
    let pi = ref (parent i) in
    let i = ref i in
    while !i <> 0 && cmp x (Vec.get heap !pi) do
      Vec.set heap !i (Vec.get heap !pi);
      Vec.set indices (Vec.get heap !i) !i;
      i  := !pi;
      pi := parent !i
    done;
    Vec.set heap !i x;
    Vec.set indices x !i

  let percolate_down cmp {heap=heap;indices=indices} i = 
    let x = Vec.get heap i in
    let sz = Vec.size heap in
    let li = ref (left i) in
    let ri = ref (right i) in
    let i = ref i in
    (try
       while !li < sz do
         let child = 
           if !ri < sz && cmp (Vec.get heap !ri) (Vec.get heap !li) then !ri
           else !li 
         in
         if not (cmp (Vec.get heap child) x) then raise Exit;
         Vec.set heap !i (Vec.get heap child);
         Vec.set indices (Vec.get heap !i) !i;
         i  := child;
         li := left !i;
         ri := right !i
       done;
     with Exit -> ());
    Vec.set heap !i x;
    Vec.set indices x !i

  let in_heap s n = 
    try n < Vec.size s.indices && Vec.get s.indices n >= 0
    with Not_found -> false

  let decrease cmp s n = 
    assert (in_heap s n); percolate_up cmp s (Vec.get s.indices n)
      
  let increase cmp s n = 
    assert (in_heap s n); percolate_down cmp s (Vec.get s.indices n)

  let filter s filt cmp = 
    let j = ref 0 in
    let lim = Vec.size s.heap in
    for i = 0 to lim - 1 do
      if filt (Vec.get s.heap i) then begin
        Vec.set s.heap !j (Vec.get s.heap i);
        Vec.set s.indices (Vec.get s.heap i) !j;
        incr j;
      end
      else Vec.set s.indices (Vec.get s.heap i) (-1);
    done;
    Vec.shrink s.heap (lim - !j);
    for i = (lim / 2) - 1 downto 0 do
      percolate_down cmp s i
    done

  let size s = Vec.size s.heap
    
  let is_empty s = Vec.is_empty s.heap
    
  let insert cmp s n =
    if not (in_heap s n) then 
      begin
        Vec.set s.indices n (Vec.size s.heap);
        Vec.push s.heap n;
        percolate_up cmp s (Vec.get s.indices n)
      end

  let grow_to_by_double s sz = 
    Vec.grow_to_by_double s.indices sz;
    Vec.grow_to_by_double s.heap sz

(*
  let update cmp s n = 
  assert (heap_property cmp s);
  begin
  if in_heap s n then 
  begin
  percolate_up cmp s (Vec.get s.indices n);
  percolate_down cmp s (Vec.get s.indices n)
  end 
  else insert cmp s n
  end;
  assert (heap_property cmp s)
*)

  let remove_min cmp ({heap=heap; indices=indices} as s) = 
    let x = Vec.get heap 0 in
    Vec.set heap 0 (Vec.last heap); (*heap.last()*)
    Vec.set indices (Vec.get heap 0) 0;
    Vec.set indices x (-1);
    Vec.pop s.heap;
    if Vec.size s.heap > 1 then percolate_down cmp s 0;
    x

end

module type STT = sig
  type var = 
      { vid : int;
        pa : atom;
        na : atom;
        mutable weight : float;
        mutable sweight : int;
        mutable seen : bool;
        mutable level : int;
        mutable index : int;
        mutable reason : reason;
        mutable vpremise : premise }
        
  and atom = 
      { var : var;
        lit : Literal.LT.t;
        neg : atom;
        mutable watched : clause Vec.t;
        mutable is_true : bool;
        aid : int }

  and clause = 
      { name : string;
        mutable atoms : atom Vec.t;
        mutable activity : float;
        mutable removed : bool;
        learnt : bool;
        cpremise : premise;
        form : Formula.t}

  and reason = clause option

  and premise = clause list

  (*module Make (Dummy : sig end) : sig*)
      
  val literal : atom -> Literal.LT.t
  val weight : atom -> float
  val is_true : atom -> bool
  val level : atom -> int
  val index : atom -> int
  val neg : atom -> atom

  val cpt_mk_var : int ref
  val ma : var Literal.LT.Map.t ref

  val dummy_var : var
  val dummy_atom : atom
  val dummy_clause : clause

  val make_var : Literal.LT.t -> var * bool

  val add_atom : Literal.LT.t -> atom 
  val vrai_atom  : atom
  val faux_atom  : atom

  val make_clause : string -> atom list -> Formula.t -> int -> bool -> 
    premise-> clause 

  val fresh_name : unit -> string

  val fresh_lname : unit -> string

  val fresh_dname : unit -> string

  val to_float : int -> float

  val to_int : float -> int
  val made_vars_info : unit -> int * var list
  val clear : unit -> unit

  (****)

  val cmp_atom : atom -> atom -> int
  val eq_atom   : atom -> atom -> bool
  val hash_atom  : atom -> int
  val tag_atom   : atom -> int

  val cmp_var : var -> var -> int
  val eq_var   : var -> var -> bool
  val h_var    : var -> int
  val tag_var  : var -> int

  (*end*)
    
  val pr_atom : Format.formatter -> atom -> unit
    
  val pr_clause : Format.formatter -> clause -> unit

end
module Types (*: STT*) = struct

  let ale = Hstring.make "<=" 
  let alt = Hstring.make "<"
  let agt = Hstring.make ">"

  let is_le n = Hstring.compare n ale = 0
  let is_lt n = Hstring.compare n alt = 0
  let is_gt n = Hstring.compare n agt = 0


  type var =
      {  vid : int;
         pa : atom;
         na : atom;
         mutable weight : float;
         mutable sweight : int;
         mutable seen : bool;
         mutable level : int;
         mutable index : int;
         mutable reason: reason;
         mutable vpremise : premise}
        
  and atom = 
      { var : var;
        lit : Literal.LT.t;
        neg : atom;
        mutable watched : clause Vec.t;
        mutable is_true : bool;
        aid : int }

  and clause = 
      { name : string; 
        mutable atoms : atom Vec.t ; 
        mutable activity : float;
        mutable removed : bool;
        learnt : bool;
        cpremise : premise;
        form : Formula.t}

  and reason = clause option

  and premise = clause list

  (*module Make (Dummy : sig end) = struct*)

  let dummy_lit = Literal.LT.vrai

  let vraie_form = Formula.mk_lit dummy_lit 0

  let rec dummy_var =
    { vid = -101;
      pa = dummy_atom;
      na = dummy_atom; 
      level = -1;
      index = -1;
      reason = None;
      weight = -1.;
      sweight = 0;
      seen = false;
      vpremise = [] }
  and dummy_atom = 
    { var = dummy_var; 
      lit = dummy_lit;
      watched = {Vec.dummy=dummy_clause; data=[||]; sz=0};
      neg = dummy_atom;
      is_true = false;
      aid = -102 }
  and dummy_clause = 
    { name = ""; 
      atoms = {Vec.dummy=dummy_atom; data=[||]; sz=0};
      activity = -1.;
      removed = false;
      learnt = false;
      cpremise = [];
      form = vraie_form }


  module Debug = struct
      
    let sign a = if a==a.var.pa then "" else "-"
        
    let level a =
      match a.var.level, a.var.reason with 
        | n, _ when n < 0 -> assert false
        | 0, Some c -> sprintf "->0/%s" c.name
        | 0, None   -> "@0"
        | n, Some c -> sprintf "->%d/%s" n c.name
        | n, None   -> sprintf "@@%d" n

    let value a = 
      if a.is_true then sprintf "[T%s]" (level a)
      else if a.neg.is_true then sprintf "[F%s]" (level a)
      else ""

    let value_ms_like a = 
      if a.is_true then sprintf ":1%s" (level a)
      else if a.neg.is_true then sprintf ":0%s" (level a)
      else ":X"

    let premise fmt v = 
      List.iter (fun {name=name} -> fprintf fmt "%s," name) v

    let atom fmt a = 
      fprintf fmt "%s%d%s [index=%d | lit:%a] vpremise={{%a}}" 
        (sign a) (a.var.vid+1) (value a) a.var.index Literal.LT.print a.lit
        premise a.var.vpremise


    let atoms_list fmt l = List.iter (fprintf fmt "%a ; " atom) l
    let atoms_array fmt arr = Array.iter (fprintf fmt "%a ; " atom) arr

    let atoms_vec fmt vec = 
      for i = 0 to Vec.size vec - 1 do
        fprintf fmt "%a ; " atom (Vec.get vec i)
      done

    let clause fmt {name=name; atoms=arr; cpremise=cp} =
      fprintf fmt "%s:{ %a} cpremise={{%a}}" name atoms_vec arr premise cp

  end

  let pr_atom = Debug.atom
  let pr_clause = Debug.clause

  module MA = Literal.LT.Map
    
  let ale = Hstring.make "<=" 
  let alt = Hstring.make "<"
  let agt = Hstring.make ">"
  let is_le n = Hstring.compare n ale = 0
  let is_lt n = Hstring.compare n alt = 0
  let is_gt n = Hstring.compare n agt = 0

  let normal_form lit = (* XXX do better *)
    let av, is_neg = Literal.LT.atom_view lit in
    (if is_neg then Literal.LT.neg lit else lit), is_neg
      
  let max_depth a = 
    let l = match Literal.LT.view a with
      | Literal.Eq (s,t) ->  [s;t]
      | Literal.Distinct(_,l) -> l
      | Literal.Builtin (_,_,l) -> l
      | Literal.Pred (p,_) -> [p]
    in
    List.fold_left (fun z t -> max z (Term.view t).Term.depth) 0 l

  let literal a = a.lit
  let weight a = a.var.weight

  let is_true a = a.is_true
  let level a = a.var.level
  let index a = a.var.index
  let neg a = a.neg

  let cpt_mk_var = ref 0
  let ma = ref MA.empty
  let make_var =
    fun lit ->
      let lit, negated = normal_form lit in
      try MA.find lit !ma, negated 
      with Not_found ->
        let cpt_fois_2 = !cpt_mk_var lsl 1 in
        let rec var  = 
	  { vid = !cpt_mk_var; 
	    pa = pa;
	    na = na; 
	    level = -1;
	    index = -1;
            reason = None;
	    weight = 0.;
            sweight = max_depth lit;
	    seen = false;
	    vpremise = [];
	  }
        and pa = 
	  { var = var; 
	    lit = lit;
	    watched = Vec.make 10 dummy_clause; 
	    neg = na;
	    is_true = false;
	    aid = cpt_fois_2 (* aid = vid*2 *) }
        and na = 
	  { var = var;
	    lit = Literal.LT.neg lit;
	    watched = Vec.make 10 dummy_clause;
	    neg = pa;
	    is_true = false;
	    aid = cpt_fois_2 + 1 (* aid = vid*2+1 *) } in 
        ma := MA.add lit var !ma;
        incr cpt_mk_var;
        var, negated

  let made_vars_info () =
    !cpt_mk_var, MA.fold (fun lit var acc -> var::acc)!ma []

  let add_atom lit =
    let var, negated = make_var lit in
    if negated then var.na else var.pa 


  let get_var lit =
    let lit, negated = normal_form lit in
    try MA.find lit !ma, negated 
    with Not_found -> assert false

  let vrai_atom = 
    let a = add_atom Literal.LT.vrai in
    a.is_true <- true;
    a.var.level <- 0;
    a.var.reason <- None;
    a
      
  let faux_atom = vrai_atom.neg

  let make_clause name ali f sz_ali is_learnt premise = 
    let atoms = Vec.from_list ali sz_ali dummy_atom in
    { name  = name;
      atoms = atoms;
      removed = false;
      learnt = is_learnt;
      activity = 0.;
      cpremise = premise;
      form = f}
      
  let fresh_lname =
    let cpt = ref 0 in 
    fun () -> incr cpt; "L" ^ (string_of_int !cpt)

  let fresh_dname =
    let cpt = ref 0 in 
    fun () -> incr cpt; "D" ^ (string_of_int !cpt)
      
  let fresh_name =
    let cpt = ref 0 in 
    fun () -> incr cpt; "C" ^ (string_of_int !cpt)



  module Clause = struct
      
    let size c = Vec.size c.atoms
    let pop c = Vec.pop c.atoms
    let shrink c i = Vec.shrink  c.atoms i
    let last c = Vec.last c.atoms
    let get c i = Vec.get c.atoms i
    let set c i v = Vec.set c.atoms i v

  end

  let to_float i = float_of_int i

  let to_int f = int_of_float f

  let clear () =
    cpt_mk_var := 0;
    ma := MA.empty

  (*end*)

  let cmp_var v1 v2 = v1.vid - v2.vid
  let eq_var v1 v2 = v1.vid - v2.vid = 0
  let tag_var v = v.vid
  let h_var v = v.vid

  let cmp_atom a1 a2 = a1.aid - a2.aid
  let eq_atom   a1 a2 = a1.aid - a2.aid = 0
  let hash_atom a1 = a1.aid
  let tag_atom  a1 = a1.aid

end

(******************************************************************************)
module type FF_SIG = sig
  type t
  type view = private UNIT of Types.atom | AND of t list | OR of t list
      
  val equal   : t -> t -> bool
  val compare : t -> t -> int
  val print   : Format.formatter -> t -> unit
  val print_stats : Format.formatter -> unit
  val vrai    : t
  val faux    : t
  val view    : t -> view
  val mk_lit  : Literal.LT.t -> t
  val mk_and  : t list -> t
  val mk_or   : t list -> t
  val mk_not  : t -> t

  val simplify :
    Formula.t -> 
    (Formula.t -> t * 'a) -> 
    t * (Formula.t * (t * Types.atom)) list

  val cnf : t ->
    Types.atom list list 
    * Types.atom list list 
    * Types.atom list

  module Set : Set.S with type elt = t
  module Map : Map.S with type key = t
end

module Flat_Formula : FF_SIG = struct 

  type view = UNIT of Types.atom | AND  of t list | OR of t list
  and t = { pos : view ; neg : view; tpos : int; tneg : int }

  let mk_not {pos=pos; neg=neg;tpos=tpos; tneg=tneg} =
    {pos=neg; neg=pos;tpos=tneg; tneg=tpos}

  module HC = 
    Hashcons.Make
      (struct
        type t' = t
        type t  = t'
            
        let tag tag f = { f with tpos = 2*tag; tneg = 2*tag+1 }
          
        let equal f1 f2 = 
          let eq_aux c1 c2 = match c1, c2 with
            | UNIT x , UNIT y -> Types.eq_atom x y
            | AND u  , AND v | OR u , OR v  -> 
              (try
                 List.iter2
                   (fun x y -> if x.tpos <> y.tpos then raise Exit) u v; true
               with Exit | Invalid_argument "List.iter2" -> false)

            | _, _ -> false
	  in
          eq_aux f1.pos f2.pos
            
        let hash f = 
          let h_aux f = match f with
            | UNIT a -> Types.hash_atom a
            | AND l  -> List.fold_left (fun acc f -> acc * 19 + f.tpos) 1 l
            | OR l   -> List.fold_left (fun acc f -> acc * 23 + f.tpos) 1 l
          in  
          let h = h_aux f.pos in
          match f.pos with
            | UNIT _ -> abs (3 * h)
            | AND _  -> abs (3 * h + 1)
            | OR _   -> abs (3 * h + 2)

        let neg f = mk_not f

       end)
      
  let cpt = ref 0

  let sp() = let s = ref "" in for i = 1 to !cpt do s := " " ^ !s done; !s ^ !s

  let rec print fmt fa = match fa.pos with
    | UNIT a -> fprintf fmt "%a" Types.pr_atom a
    | AND s  -> 
      incr cpt;
      fprintf fmt "(and%a" print_list s;
      decr cpt;
      fprintf fmt "@.%s)" (sp())
        
    | OR s   -> 
      incr cpt;
      fprintf fmt "(or%a" print_list s;
      decr cpt;
      fprintf fmt "@.%s)" (sp())

  and print_list fmt l =
    match l with
      | [] -> assert false
      | e::l ->
        fprintf fmt "@.%s%a" (sp()) print e;
        List.iter(fprintf fmt "@.%s%a" (sp()) print) l
          

  let print fmt f = cpt := 0; print fmt f

  let print_stats fmt = ()

  let compare f1 f2 = f1.tpos - f2.tpos
    
  let equal f1 f2 = f1.tpos - f2.tpos = 0
  let hash f = f.tpos
  let tag  f = f.tpos
  let view f = f.pos

  let make pos neg = 
    HC.hashcons {pos=pos ; neg=neg; tpos= -1; tneg= -1 (*dump*) }

  let aaz a = assert (a.Types.var.Types.level = 0)
    
  let complements f1 f2 = f1.tpos - f2.tneg = 0

  let mk_lit a = 
    let at = Types.add_atom a in 
    if at == at.Types.var.Types.pa then make (UNIT at) (UNIT at.Types.neg)
    else mk_not (make (UNIT at.Types.neg) (UNIT at))

  let vrai = mk_lit Literal.LT.vrai
  let faux = mk_not vrai

  let merge_and_check l1 l2 =
    let rec merge_rec l1 l2 hd =
      match l1, l2 with
        | [], l2 -> l2
        | l1, [] -> l1
        | h1 :: t1, h2 :: t2 ->
          let c = compare h1 h2 in
          if c = 0 then merge_rec l1 t2 hd
          else 
            if compare h1 h2 < 0
            then begin
              if complements hd h1 then raise Exit;
              h1 :: merge_rec t1 l2 h1
            end
            else begin
              if complements hd h2 then raise Exit;
              h2 :: merge_rec l1 t2 h2
            end
    in
    match l1, l2 with
      | [], l2 -> l2
      | l1, [] -> l1
      | h1 :: t1, h2 :: t2 ->
        let c = compare h1 h2 in
        if c = 0 then merge_rec t1 l2 h1
        else 
          if compare h1 h2 < 0
          then merge_rec l1 l2 h1
          else merge_rec l1 l2 h2

  let mk_and l = 
    try 
      let so, nso = 
        List.fold_left
          (fun ((so,nso) as acc) e -> 
            match e.pos with 
              | AND l -> merge_and_check so l, nso
              | UNIT a when a.Types.var.Types.level = 0 -> 
                if a.Types.neg.Types.is_true then (aaz a; raise Exit); (* XXX*)
                if a.Types.is_true then (aaz a; acc)
                else so, e::nso
              | _     -> so, e::nso
          )([],[]) l
      in 
      let delta_inv = List.fast_sort (fun a b -> compare b a) nso in
      let delta_u = match delta_inv with
        | [] -> delta_inv
        | e::l ->
          let _, delta_u = 
            List.fold_left
              (fun ((c,l) as acc) e ->
                if complements c e then raise Exit;
                if equal c e then acc
                else (e, e::l)
              )(e,[e]) l
          in 
          delta_u
      in
      match merge_and_check so delta_u with
        | [] -> vrai
        | [e]-> e
        | l -> make (AND l) (OR (List.rev (List.rev_map mk_not l)))
    with Exit -> faux

  (* res = l1 inter l2 *)
  let intersect_list l1 l2 =
    let rec inter l1 l2 acc =
      match l1, l2 with
        | [], _ | _ , [] -> List.rev acc
        | f1::r1, f2::r2 ->
          let c = compare f1 f2 in
          if c = 0 then inter r1 r2 (f1::acc)
          else if c > 0 then inter l1 r2 acc else inter r1 l2 acc
    in
    inter l1 l2 []
      
  exception Not_included 

  let remove_elt e l = 
    let rec relt l acc =
      match l with
        | [] -> raise Not_included
        | f::r ->
          let c = compare f e in
          if c = 0 then List.rev_append acc r
          else if c < 0 then relt r (f::acc) 
          else raise Not_included
    in
    relt l []

  let diff_list to_exclude l = 
    let rec diff l1 l2 acc =
      match l1, l2 with
        | [], [] -> List.rev acc
        | [], r  -> List.rev_append acc r
        | _ , [] -> raise Not_included
        | f1::r1, f2::r2 ->
          let c = compare f1 f2 in
          if c = 0 then diff r1 r2 acc
          else if c > 0 then diff l1 r2 (f2::acc) 
          else raise Not_included
    in
    diff to_exclude l []

  let extract_common l = 
    let atoms, ands = 
      List.fold_left
        (fun (atoms, ands) f ->
          match view f with
            | OR _   -> assert false
            | UNIT a -> f::atoms, ands
            | AND l  -> atoms, l::ands
        )([],[]) l
    in
    match atoms, ands with
      | [], [] -> assert false        

      | _::_::_, _ -> 
        if debug () then
          fprintf fmt "Failure: many distinct atoms@.";
        None
          
      | [_] as common, _ ->
        if debug () then 
          fprintf fmt "TODO: Should have one toplevel common atom@.";
        begin 
          try 
            (*  a + (a . B_1) + ... (a . B_n) = a *)
            ignore (List.rev_map (diff_list common) ands);
            Some (common, [[]])
          with Not_included -> None
        end
          
      | [], ad::ands' ->
        if debug () then
          fprintf fmt "Should look for internal common parts@.";
        let common = List.fold_left intersect_list ad ands' in
        match common with
            [] -> None
          | _ -> 
            try Some (common, List.rev_map (diff_list common) ands)
            with Not_included -> assert false

  let rec mk_or l = 
    try 
      let so, nso = 
        List.fold_left
          (fun ((so,nso) as acc) e -> 
            match e.pos with 
              | OR l  -> merge_and_check so l, nso
              | UNIT a  when a.Types.var.Types.level = 0 -> 
                if a.Types.is_true then (aaz a; raise Exit); (* XXX *)
                if a.Types.neg.Types.is_true then (aaz a; acc)
                else so, e::nso
              | _     -> so, e::nso
          )([],[]) l
      in 
      let delta_inv = List.fast_sort (fun a b -> compare b a) nso in
      let delta_u = match delta_inv with
        | [] -> delta_inv
        | e::l ->
          let _, delta_u = 
            List.fold_left
              (fun ((c,l) as acc) e ->
                if complements c e then raise Exit;
                if equal c e then acc
                else (e, e::l)
              )(e,[e]) l
          in 
          delta_u
      in
      match merge_and_check so delta_u with
        | [] -> faux
        | [e]-> e
        | l  ->
          match extract_common l with
            | None ->
              begin match l with
                | [{pos=UNIT _} as fa;{pos=AND ands}] ->
                  begin 
                    try mk_or [fa ; (mk_and (remove_elt (mk_not fa) ands))]
                    with Not_included -> 
                      make (OR l) (AND (List.rev (List.rev_map mk_not l)))
                  end
                | _ -> make (OR l) (AND (List.rev (List.rev_map mk_not l)))
              end
            | Some (com,ands) ->
              let ands = List.rev_map mk_and ands in
              mk_and ((mk_or ands) :: com)
    with Exit -> vrai

  (* translation from Formula.t *)

  let abstract_lemma abstr f tl lem =
    try fst (abstr f)
    with Not_found ->
      try fst (List.assoc f !lem)
      with Not_found ->
        if tl then begin
          lem := (f, (vrai, Types.vrai_atom)) :: !lem;
          vrai
        end
        else
          let lit = A.mk_pred (T.fresh_name Ty.Tbool) false in
          let xlit = mk_lit lit in
          lem := (f, (xlit, Types.add_atom lit)) :: !lem;
          xlit

  let simplify f abstr =
    let lem = ref [] in
    let rec simp topl f = 
      match F.view f with
        | F.Literal a -> mk_lit a
        | F.Lemma _   -> abstract_lemma abstr f topl lem
          
        | F.Skolem {F.sko_subst=s; sko_f=fs} -> 
          mk_not (simp false (F.mk_not f))

        | F.Unit(f1, f2) ->
          let x1 = simp topl f1 in
          let x2 = simp topl f2 in
          begin match x1.pos , x2.pos with
            | AND l1, AND l2 -> mk_and (List.rev_append l1 l2)
            | AND l1, _      -> mk_and (x2 :: l1)
            | _     , AND l2 -> mk_and (x1 :: l2)
            | _              -> mk_and [x1; x2]
          end
            
        | F.Clause(f1, f2) ->
          let x1 = simp false f1 in
          let x2 = simp false f2 in
          begin match x1.pos, x2.pos with
            | OR l1, OR l2 -> mk_or (List.rev_append l1 l2)
            | OR l1, _     -> mk_or (x2 :: l1)
            | _    , OR l2 -> mk_or (x1 :: l2)
            | _            -> mk_or [x1; x2]
          end
            

        | F.Let {F.let_var=lvar; let_term=lterm; let_subst=s; let_f=lf} ->
          let f' = F.apply_subst s lf in
          let v = Symbols.Map.find lvar (fst s) in
          let at = mk_lit (A.mk_eq v lterm) in
          let res = simp topl f' in
          begin match res.pos with
            | AND l -> mk_and (at :: l)
            | _     -> mk_and [at; res]
          end
    in
    simp true f, !lem

  (* CNF a la Tseitin *)

  let atom_of_lit lit is_neg = 
    let a = Types.add_atom lit in if is_neg then a.Types.neg else a

  let mk_proxy n =
    let hs = Hs.make ("PROXY__" ^ (string_of_int n)) in
    let sy = Symbols.Name(hs, Symbols.Other) in
    A.mk_pred (Term.make sy [] Ty.Tbool) false

  let cnf_aux f acc_or acc_and = 
    let rec cnf_rec f = match f.pos with
      | UNIT a -> [a]
      | AND l -> 
        List.fold_left 
          (fun acc f -> 
            match cnf_rec f with (* retourne un OU *)
              | [] -> assert false
              | [a] -> a :: acc
              | l ->
                let proxy = atom_of_lit (mk_proxy f.tpos) false in
                acc_or := (proxy, l) :: !acc_or;
                proxy :: acc
          )[] l
          
      | OR l -> 
        List.fold_left
          (fun acc f ->
            match cnf_rec f with (* retourne un ET *)
              | []  -> assert false
              | [a] -> a :: acc
              | l   -> 
                let proxy = atom_of_lit (mk_proxy f.tpos) false in
                acc_and := (proxy, l) :: !acc_and;
                proxy :: acc
          )[] l
    in
    cnf_rec f

  let cnf f = 
    let acc_or = ref [] in
    let acc_and = ref [] in
    let acc = match f.pos with
      | AND l -> List.rev_map (fun f -> cnf_aux f acc_or acc_and) l
      | _ -> [cnf_aux f acc_or acc_and]
    in
    let proxies = ref [] in
    let acc = 
      List.fold_left
        (fun acc (p,l) ->
          proxies := p :: !proxies;
          let np = p.Types.neg in
          let cl, acc = 
            List.fold_left
              (fun (cl,acc) a -> (a.Types.neg :: cl), [np; a] :: acc)([p],acc) l in
          cl :: acc
        )acc !acc_and
    in
    let acc = 
      List.fold_left
        (fun acc (p,l) ->
          proxies := p :: !proxies;
          let acc = List.fold_left (fun acc a -> [p;a.Types.neg]::acc) acc l in
          ((p.Types.neg) :: l) :: acc
        )acc !acc_or
    in
    let unit, non_unit = 
      List.fold_left
        (fun (u,nu) c -> 
          match c with [] -> assert false |[_] -> c::u, nu | _  -> u, c::nu)
        ([],[]) acc
    in
    unit, non_unit, !proxies

  module Set = Set.Make(struct type t'=t type t=t' let compare=compare end)
  module Map = Map.Make(struct type t'=t type t=t' let compare=compare end)

end
  
(******************************************************************************)

open Types

module Ex = Explanation

exception Sat
exception Unsat of clause list
exception Restart

let vraie_form = Formula.vrai


module type SAT_ML = sig
  (*module Make (Dummy : sig end) : sig*)
  type state
  type th

  val solve : unit -> unit
  val assume : Types.atom list list -> Formula.t -> cnumber : int -> unit

  val boolean_model : unit -> Types.atom list
  val current_tbox : unit -> th
  val empty : unit -> unit
  val clear : unit -> unit

  val save : unit -> state
  val restore : state -> unit

  val start : unit -> unit
  val stop : unit -> int64

(*end*)
end

module Make (Th : Theory.S) : SAT_ML with type th = Th.t = struct


  type th = Th.t
  type env = 
      { 
      (* si vrai, les contraintes sont deja fausses *)
        mutable is_unsat : bool;

        mutable unsat_core : clause list;

      (* clauses du probleme *)
        mutable clauses : clause Vec.t;
        
      (* clauses apprises *)
        mutable learnts : clause Vec.t;
        
      (* valeur de l'increment pour l'activite des clauses *)
        mutable clause_inc : float;
        
      (* valeur de l'increment pour l'activite des variables *)
        mutable var_inc : float;
        
      (* un vecteur des variables du probleme *)
        mutable vars : var Vec.t;
        
      (* la pile de decisions avec les faits impliques *)
        mutable trail : atom Vec.t;

      (* une pile qui pointe vers les niveaux de decision dans trail *)
        mutable trail_lim : int Vec.t;

      (* Tete de la File des faits unitaires a propager. 
	 C'est un index vers le trail *)
        mutable qhead : int;
        
      (* Nombre des assignements top-level depuis la derniere 
         execution de 'simplify()' *)
        mutable simpDB_assigns : int;

      (* Nombre restant de propagations a faire avant la prochaine 
         execution de 'simplify()' *)
        mutable simpDB_props : int;

      (* Un tas ordone en fonction de l'activite des variables *)
        mutable order : Iheap.t;

      (* estimation de progressions, mis a jour par 'search()' *)
        mutable progress_estimate : float;

      (* *)
        remove_satisfied : bool;

      (* inverse du facteur d'acitivte des variables, vaut 1/0.999 par defaut *)
        var_decay : float;

      (* inverse du facteur d'activite des clauses, vaut 1/0.95 par defaut *)
        clause_decay : float;

      (* la limite de restart initiale, vaut 100 par defaut *)
        mutable restart_first : int;

      (* facteur de multiplication de restart limite, vaut 1.5 par defaut*)
        restart_inc : float;
        
      (* limite initiale du nombre de clause apprises, vaut 1/3 
         des clauses originales par defaut *)
        mutable learntsize_factor : float;
        
      (* multiplier learntsize_factor par cette valeur a chaque restart, 
         vaut 1.1 par defaut *)
        learntsize_inc : float;

      (* controler la minimisation des clauses conflit, vaut true par defaut *)
        expensive_ccmin : bool;

      (* controle la polarite a choisir lors de la decision *)
        polarity_mode : bool;
        
        mutable starts : int;

        mutable decisions : int;

        mutable propagations : int;

        mutable conflicts : int;

        mutable clauses_literals : int;

        mutable learnts_literals : int;

        mutable max_literals : int;

        mutable tot_literals : int;

        mutable nb_init_vars : int;

        mutable nb_init_clauses : int;
        
        mutable model : var Vec.t;
        
        mutable tenv : Th.t;

        mutable tenv_queue : Th.t Vec.t;
        
        mutable tatoms_queue : atom Queue.t;

      }
        


  exception Conflict of clause
  (*module Make (Dummy : sig end) = struct*)

  module Solver_types = Types(*.Make(struct end)*)

  let steps = ref 0L

  let start () = steps := 0L
  let stop () = !steps

  open Solver_types

  type state = 
      {
        env : env; 
        st_cpt_mk_var: int;
        st_ma : var Literal.LT.Map.t;
      }


  let env =
    { 
      is_unsat = false;   
      
      unsat_core = [] ;

      clauses = Vec.make 0 dummy_clause; (*sera mis a jour lors du parsing*)
      
      learnts = Vec.make 0 dummy_clause; (*sera mis a jour lors du parsing*)
      
      clause_inc = 1.;
      
      var_inc = 1.;
      
      vars = Vec.make 0 dummy_var; (*sera mis a jour lors du parsing*)
      
      trail = Vec.make 601 dummy_atom;

      trail_lim = Vec.make 601 (-105);

      qhead = 0;
      
      simpDB_assigns = -1;

      simpDB_props = 0;

      order = Iheap.init 0; (* sera mis a jour dans solve *)

      progress_estimate = 0.;

      remove_satisfied = true;

      var_decay = 1. /. 0.95;

      clause_decay = 1. /. 0.999;

      restart_first = 100;

      restart_inc = 1.5;
      
      learntsize_factor = 1. /. 3. ;
      
      learntsize_inc = 1.1;

      expensive_ccmin = true;

      polarity_mode = false;
      
      starts = 0;

      decisions = 0;

      propagations = 0;

      conflicts = 0;

      clauses_literals = 0;

      learnts_literals = 0;

      max_literals = 0;

      tot_literals = 0;

      nb_init_vars = 0;

      nb_init_clauses = 0;
      
      model = Vec.make 0 dummy_var;
      
      tenv = Th.empty();

      tenv_queue = Vec.make 100 (Th.empty());

      tatoms_queue = Queue.create ();

    }

      
(*
  module SA = Set.Make
  (struct
  type t = Types.atom
  let compare a b = a.Types.aid - b.Types.aid
  end)

  module SSA = Set.Make(SA)


  let ssa = ref SSA.empty

  let clause_exists atoms =
  try
(*List.iter
  (fun a -> if a.is_true then raise Exit) atoms;*)
  let sa = List.fold_left (fun s e -> SA.add e s) SA.empty atoms in
  if SSA.mem sa !ssa then true
  else begin
  ssa := SSA.add sa !ssa;
  false
  end
  with Exit -> true

  let f_weight i j = 
  let vj = Vec.get env.vars j in
  let vi = Vec.get env.vars i in
(*if vi.sweight <> vj.sweight then vi.sweight < vj.sweight
  else*) vj.weight < vi.weight
*)

  let f_weight i j = (Vec.get env.vars j).weight < (Vec.get env.vars i).weight
    
  let f_filter i = (Vec.get env.vars i).level < 0

  let insert_var_order v =
    Iheap.insert f_weight env.order v.vid

  let var_decay_activity () = env.var_inc <- env.var_inc *. env.var_decay
    
  let clause_decay_activity () = 
    env.clause_inc <- env.clause_inc *. env.clause_decay

  let var_bump_activity v = 
    v.weight <- v.weight +. env.var_inc;
    if v.weight > 1e100 then begin
      for i = 0 to env.vars.Vec.sz - 1 do
        (Vec.get env.vars i).weight <- (Vec.get env.vars i).weight *. 1e-100
      done;
      env.var_inc <- env.var_inc *. 1e-100;
    end;
    if Iheap.in_heap env.order v.vid then
      Iheap.decrease f_weight env.order v.vid
        

  let clause_bump_activity c = 
    c.activity <- c.activity +. env.clause_inc;
    if c.activity > 1e20 then begin
      for i = 0 to env.learnts.Vec.sz - 1 do
        (Vec.get env.learnts i).activity <-
          (Vec.get env.learnts i).activity *. 1e-20;
      done;
      env.clause_inc <- env.clause_inc *. 1e-20
    end

  let decision_level () = Vec.size env.trail_lim

  let nb_assigns () = Vec.size env.trail
  let nb_clauses () = Vec.size env.clauses
  let nb_learnts () = Vec.size env.learnts
  let nb_vars    () = Vec.size env.vars

  let new_decision_level() = 
    Vec.push env.trail_lim (Vec.size env.trail);
    Vec.push env.tenv_queue env.tenv (* save the current tenv *)

  let attach_clause c = 
    Vec.push (Vec.get c.atoms 0).neg.watched c;
    Vec.push (Vec.get c.atoms 1).neg.watched c;
    if c.learnt then 
      env.learnts_literals <- env.learnts_literals + Vec.size c.atoms
    else
      env.clauses_literals <- env.clauses_literals + Vec.size c.atoms
        
  let detach_clause c = 
    c.removed <- true;
  (*
    Vec.remove (Vec.get c.atoms 0).neg.watched c;
    Vec.remove (Vec.get c.atoms 1).neg.watched c;
  *)
    if c.learnt then 
      env.learnts_literals <- env.learnts_literals - Vec.size c.atoms
    else
      env.clauses_literals <- env.clauses_literals - Vec.size c.atoms

  let remove_clause c = detach_clause c

  let satisfied c = 
    try
      for i = 0 to Vec.size c.atoms - 1 do
        if (Vec.get c.atoms i).is_true then raise Exit
      done;
      false
    with Exit -> true

(* annule tout jusqu'a lvl *exclu*  *)
  let cancel_until lvl = 
    if decision_level () > lvl then begin
      env.qhead <- Vec.get env.trail_lim lvl;
      for c = Vec.size env.trail - 1 downto env.qhead do
        let a = Vec.get env.trail c in
        a.is_true <- false;
        a.neg.is_true <- false;
        a.var.level <- -1;
        a.var.index <- -1;
        a.var.reason <- None;
        a.var.vpremise <- [];
        insert_var_order a.var
      done;
      Queue.clear env.tatoms_queue;
      env.tenv <- Vec.get env.tenv_queue lvl; (* recover the right tenv *)
      Vec.shrink env.trail ((Vec.size env.trail) - env.qhead);
      Vec.shrink env.trail_lim ((Vec.size env.trail_lim) - lvl);
      Vec.shrink env.tenv_queue ((Vec.size env.tenv_queue) - lvl)
    end;
    assert (Vec.size env.trail_lim = Vec.size env.tenv_queue)

  let rec pick_branch_var () =
    if Iheap.size env.order = 0 then raise Sat;
    let max = Iheap.remove_min f_weight env.order in
    let v = Vec.get env.vars max in
    if v.level>= 0 then  begin
      assert (v.pa.is_true || v.na.is_true);
      pick_branch_var ()
    end
    else v

  let pick_branch_lit () = 
    let v = pick_branch_var () in
    v.na

  let enqueue a lvl reason =
    assert (not a.is_true && not a.neg.is_true && 
              a.var.level < 0 && a.var.reason = None && lvl >= 0);
  (* Garder la reason car elle est utile pour les unsat-core *)
  (*let reason = if lvl = 0 then None else reason in*)
    a.is_true <- true;
    a.var.level <- lvl;
    a.var.reason <- reason;
  (*eprintf "enqueue: %a@." Debug.atom a; *)
    Vec.push env.trail a;
    a.var.index <- Vec.size env.trail

  let progress_estimate () = 
    let prg = ref 0. in
    let nbv = to_float (nb_vars()) in
    let lvl = decision_level () in 
    let _F = 1. /. nbv in
    for i = 0 to lvl do
      let _beg = if i = 0 then 0 else Vec.get env.trail_lim (i-1) in
      let _end = if i=lvl then Vec.size env.trail else Vec.get env.trail_lim i in
      prg := !prg +. _F**(to_float i) *. (to_float (_end - _beg))
    done;
    !prg /. nbv

  let propagate_in_clause a c i watched new_sz =
    let atoms = c.atoms in
    let first = Vec.get atoms 0 in
    if first == a.neg then begin (* le litiral faux doit etre dans .(1) *)
      Vec.set atoms 0 (Vec.get atoms 1);
      Vec.set atoms 1 first
    end;
    let first = Vec.get atoms 0 in
    if first.is_true then begin
    (* clause vraie, la garder dans les watched *)
      Vec.set watched !new_sz c; 
      incr new_sz;
    end
    else 
      try (* chercher un nouveau watcher *)
        for k = 2 to Vec.size atoms - 1 do
          let ak = Vec.get atoms k in
          if not (ak.neg.is_true) then begin 
          (* Watcher Trouve: mettre a jour et sortir *)
            Vec.set atoms 1 ak;
            Vec.set atoms k a.neg;
            Vec.push ak.neg.watched c;
            raise Exit
          end
        done;
      (* Watcher NON Trouve *)
          if first.neg.is_true then begin
        (* la clause est fausse *)
            env.qhead <- Vec.size env.trail;
            for k = i to Vec.size watched - 1 do
              Vec.set watched !new_sz (Vec.get watched k);
              incr new_sz;
            done;
            raise (Conflict c)
          end
          else begin
        (* la clause est unitaire *)
            Vec.set watched !new_sz c; 
            incr new_sz;
            enqueue first (decision_level ()) (Some c)
          end
      with Exit -> ()
        
  let propagate_atom a res = 
    let watched = a.watched in
    let new_sz_w = ref 0 in
    begin 
      try
        for i = 0 to Vec.size watched - 1 do
          let c = Vec.get watched i in
          if not c.removed then propagate_in_clause a c i watched new_sz_w
        done;
      with Conflict c -> assert (!res = None); res := Some c 
    end;
    let dead_part = Vec.size watched - !new_sz_w in
    Vec.shrink watched dead_part

  let expensive_theory_propagate () = None
(* try *)
(*   if D1.d then eprintf "expensive_theory_propagate@."; *)
(*   ignore(Th.expensive_processing env.tenv); *)
(*   if D1.d then eprintf "expensive_theory_propagate => None@."; *)
(*   None *)
(* with Exception.Inconsistent dep ->  *)
(*   if D1.d then eprintf "expensive_theory_propagate => Inconsistent@."; *)
(*   Some dep *)
    
  let theory_propagate () =
    let facts = ref [] in
    while not (Queue.is_empty env.tatoms_queue) do
      let a = Queue.pop env.tatoms_queue in
      let ta =  
        if a.is_true then a
        else if a.neg.is_true then a.neg (* TODO: useful ?? *)
        else assert false
      in 
      let ex = 
        if proof () || ta.var.level > 0 then Ex.singleton (Ex.Literal ta.lit)
        else Ex.empty 
      in
      facts := (ta.lit, ex) :: !facts
    done;
    try
      let full_model = nb_assigns() = env.nb_init_vars in
      env.tenv <- 
        List.fold_left 
        (fun t (a,ex) -> 
          let t,_ ,cpt = Th.assume a ex t in
          steps := Int64.add (Int64.of_int cpt) !steps;
	  if steps_bound () <> -1 
	    && Int64.compare !steps (Int64.of_int (steps_bound ())) > 0 then 
	    begin 
	      printf "Steps limit reached: %Ld@." !steps;
	      exit 1
	    end;
          t
      (* XXX what to do with the other results of Th.assume ? *)
        ) env.tenv !facts; (* facts are reverted *)
      if full_model then expensive_theory_propagate ()
      else None
    with Exception.Inconsistent (dep, terms) -> 
    (* XXX what to do with terms ? *)
    (* eprintf "th inconsistent : %a @." Ex.print dep; *)
      Some dep

  let propagate () = 
    let num_props = ref 0 in
    let res = ref None in
  (*assert (Queue.is_empty env.tqueue);*)
    while env.qhead < Vec.size env.trail do
      let a = Vec.get env.trail env.qhead in
      env.qhead <- env.qhead + 1;
      incr num_props;
      propagate_atom a res;
      Queue.push a env.tatoms_queue;
    done;
    env.propagations <- env.propagations + !num_props;
    env.simpDB_props <- env.simpDB_props - !num_props;
    !res


  let analyze c_clause = 
    let pathC  = ref 0 in
    let learnt = ref [] in
    let cond   = ref true in
    let blevel = ref 0 in
    let seen   = ref [] in
    let c      = ref c_clause in
    let tr_ind = ref (Vec.size env.trail - 1) in
    let size   = ref 1 in
    let history = ref [] in
    while !cond do
      if !c.learnt then clause_bump_activity !c;
      history := !c :: !history;
    (* visit the current predecessors *)
      for j = 0 to Vec.size !c.atoms - 1 do
        let q = Vec.get !c.atoms j in
      (*printf "I visit %a@." D1.atom q;*)
        assert (q.is_true || q.neg.is_true && q.var.level >= 0); (* Pas sur *)
        if not q.var.seen && q.var.level > 0 then begin
          var_bump_activity q.var;
          q.var.seen <- true;
          seen := q :: !seen;
          if q.var.level >= decision_level () then incr pathC
          else begin
            learnt := q :: !learnt;
            incr size;
            blevel := max !blevel q.var.level
          end
        end
      done;
      
    (* look for the next node to expand *)
      while not (Vec.get env.trail !tr_ind).var.seen do decr tr_ind done;
      decr pathC;
      let p = Vec.get env.trail !tr_ind in
      decr tr_ind;
      match !pathC, p.var.reason with
        | 0, _ -> 
          cond := false;
          learnt := p.neg :: (List.rev !learnt)
        | n, None   -> assert false
        | n, Some cl -> c := cl
    done;
    List.iter (fun q -> q.var.seen <- false) !seen;
    !blevel, !learnt, !history, !size

  let f_sort_db c1 c2 = 
    let sz1 = Vec.size c1.atoms in
    let sz2 = Vec.size c2.atoms in
    let c = compare c1.activity c2.activity in
    if sz1 = sz2 && c = 0 then 0
    else 
      if sz1 > 2 && (sz2 = 2 || c < 0) then -1
      else 1

  let locked c = false(*
                        try
                        for i = 0 to Vec.size env.vars - 1 do
                        match (Vec.get env.vars i).reason with
	                | Some c' when c ==c' -> raise Exit
	                | _ -> ()
                        done;
                        false
                        with Exit -> true*)

  let reduce_db () = ()
(*
  let extra_lim = env.clause_inc /. (to_float (Vec.size env.learnts)) in
  Vec.sort env.learnts f_sort_db;
  let lim2 = Vec.size env.learnts in
  let lim1 = lim2 / 2 in
  let j = ref 0 in
  for i = 0 to lim1 - 1 do
  let c = Vec.get env.learnts i in
  if Vec.size c.atoms > 2 && not (locked c) then 
  remove_clause c
  else 
  begin Vec.set env.learnts !j c; incr j end
  done;
  for i = lim1 to lim2 - 1 do 
  let c = Vec.get env.learnts i in
  if Vec.size c.atoms > 2 && not (locked c) && c.activity < extra_lim then
  remove_clause c
  else 
  begin Vec.set env.learnts !j c; incr j end
  done;
  Vec.shrink env.learnts (lim2 - !j)
*)

  let remove_satisfied vec = 
    let j = ref 0 in
    let k = Vec.size vec - 1 in
    for i = 0 to k do
      let c = Vec.get vec i in
      if satisfied c then remove_clause c
      else begin
        Vec.set vec !j (Vec.get vec i);
        incr j
      end
    done;
    Vec.shrink vec (k + 1 - !j)


  module HUC = Hashtbl.Make 
    (struct type t = clause let equal = (==) let hash = Hashtbl.hash end)


  let report_b_unsat ({atoms=atoms} as confl) =
    let l = ref [confl] in
    for i = 0 to Vec.size atoms - 1 do
      let v = (Vec.get atoms i).var in
      l := List.rev_append v.vpremise !l;
      match v.reason with None -> () | Some c -> l := c :: !l
    done;
    if false then begin
      eprintf "@.>>UNSAT Deduction made from:@.";
      List.iter
        (fun hc ->
          eprintf "    %a@." Types.pr_clause hc
        )!l;
    end; 
    let uc = HUC.create 17 in
    let rec roots todo = 
      match todo with
        | [] -> ()
        | c::r ->
	  for i = 0 to Vec.size c.atoms - 1 do
	    let v = (Vec.get c.atoms i).var in
	    if not v.seen then begin 
	      v.seen <- true;
	      roots v.vpremise;
	      match v.reason with None -> () | Some r -> roots [r];
	    end
	  done;
          match c.cpremise with
            | []    -> if not (HUC.mem uc c) then HUC.add uc c (); roots r
            | prems -> roots prems; roots r
    in roots !l;
    let unsat_core = HUC.fold (fun c _ l -> c :: l) uc [] in
    if false then begin
      eprintf "@.>>UNSAT_CORE:@.";
      List.iter
        (fun hc ->
          eprintf "    %a@." Types.pr_clause hc
        )unsat_core;
    end;
    env.is_unsat <- true;
    env.unsat_core <- unsat_core;
    raise (Unsat unsat_core)


  let report_t_unsat dep =
    let l = 
      Ex.fold_atoms
        (fun ex l ->
          match ex with
            | Ex.Literal lit ->
              let {var=v} = Types.add_atom lit in
              let l = List.rev_append v.vpremise l in
              begin match v.reason with
                | None -> l 
                | Some c -> c :: l
              end
            | _ -> assert false (* TODO *)
        ) dep []
    in
    if false then begin
      eprintf "@.>>T-UNSAT Deduction made from:@.";
      List.iter
        (fun hc ->
          eprintf "    %a@." Types.pr_clause hc
        )l;
    end;
    let uc = HUC.create 17 in
    let rec roots todo = 
      match todo with
        | [] -> ()
        | c::r ->
	  for i = 0 to Vec.size c.atoms - 1 do
	    let v = (Vec.get c.atoms i).var in
	    if not v.seen then begin 
	      v.seen <- true;
	      roots v.vpremise;
	      match v.reason with None -> () | Some r -> roots [r];
	    end
	  done;
          match c.cpremise with
            | []    -> if not (HUC.mem uc c) then HUC.add uc c (); roots r
            | prems -> roots prems; roots r
    in roots l;
    let unsat_core = HUC.fold (fun c _ l -> c :: l) uc [] in
    if false then begin
      eprintf "@.>>T-UNSAT_CORE:@.";
      List.iter
        (fun hc ->
          eprintf "    %a@." Types.pr_clause hc
        ) unsat_core;
    end;
    env.is_unsat <- true;
    env.unsat_core <- unsat_core;
    raise (Unsat unsat_core)

(*** experimental: taken from ctrl-ergo-2 ********************

     let rec theory_simplify () = 
     let theory_simplification = 2 in
     let assume a = 
     ignore (Th.assume a.lit Ex.empty env.tenv)
     in
     if theory_simplification >= 2 then begin
     for i = 0 to Vec.size env.vars - 1 do
     try
     let a = (Vec.get env.vars i).pa in
     if not (a.is_true || a.neg.is_true) then
     try 
     assume a;
     try assume a.neg 
     with Exception.Inconsistent _ -> 
     if debug () then
     eprintf "%a propagated m/theory at level 0@.@." Types.pr_atom a;
     enqueue a 0 None (* Mettre Some dep pour les unsat-core*)
     with Exception.Inconsistent _ ->
     if debug () then
     eprintf "%a propagated m/theory at level 0@.@." Types.pr_atom a.neg;
     enqueue a.neg 0 None (* Mettre Some dep pour les unsat-core*)
     with Not_found -> ()
     done;
     
     let head = env.qhead in
     if propagate () <> None || theory_propagate () <> None then raise (Unsat []);
     let head' = env.qhead in
     if head' > head then theory_simplify ()
     end
*)

  let simplify () = 
    assert (decision_level () = 0);
    if env.is_unsat then raise (Unsat env.unsat_core);
    begin 
      match propagate () with
        | Some confl -> report_b_unsat confl
        | None ->
          match theory_propagate () with
              Some dep -> report_t_unsat dep
            | None -> ()
    end;
    if nb_assigns() <> env.simpDB_assigns && env.simpDB_props <= 0 then begin
      if debug () then fprintf fmt "simplify@.";
    (*theory_simplify ();*)
      if Vec.size env.learnts > 0 then remove_satisfied env.learnts;
      if env.remove_satisfied then remove_satisfied env.clauses;
    (*Iheap.filter env.order f_filter f_weight;*)
      env.simpDB_assigns <- nb_assigns ();
      env.simpDB_props <- env.clauses_literals + env.learnts_literals;
    end


  let record_learnt_clause blevel learnt history size = 
    begin match learnt with
      | [] -> assert false
      | [fuip] ->
        assert (blevel = 0);
        fuip.var.vpremise <- history;
        enqueue fuip 0 None
      | fuip :: _ ->
        let name = fresh_lname () in
        let lclause = make_clause name learnt vraie_form size true history in
        Vec.push env.learnts lclause;
        attach_clause lclause;
        clause_bump_activity lclause;
        enqueue fuip blevel (Some lclause)
    end;
    var_decay_activity ();
    clause_decay_activity()

  let check_inconsistence_of dep = ()
(*
  try
  let env = ref (Th.empty()) in ();
  Ex.iter_atoms
  (fun atom ->
  let t,_,_ = Th.assume ~cs:true atom.lit (Ex.singleton atom) !env in
  env := t)
  dep;
(* ignore (Th.expensive_processing !env); *)
  assert false
  with Exception.Inconsistent _ -> ()
*)

  let theory_analyze dep = 
    let atoms, sz, max_lvl, c_hist = 
      Ex.fold_atoms
        (fun ex (acc, sz, max_lvl, c_hist) ->
          match ex with
              Ex.Literal lit ->
                let a = Types.add_atom lit in
	        let c_hist = List.rev_append a.var.vpremise c_hist in
	        let c_hist = match a.var.reason with 
	          | None -> c_hist | Some r -> r:: c_hist 
                in
	        if a.var.level = 0 then acc, sz, max_lvl, c_hist
	        else a.neg :: acc, sz + 1, max max_lvl a.var.level, c_hist
            | _ -> assert false (* TODO *)
        ) dep ([], 0, 0, [])
    in
    if atoms = [] then begin
    (* check_inconsistence_of dep; *)
      report_t_unsat dep
  (* une conjonction de faits unitaires etaient deja unsat *)
    end;
    let name = fresh_dname() in
    let c_clause = make_clause name atoms vraie_form sz false c_hist in
  (* eprintf "c_clause: %a@." Types.pr_clause c_clause; *)
    c_clause.removed <- true;

    let pathC  = ref 0 in
    let learnt = ref [] in
    let cond   = ref true in
    let blevel = ref 0 in
    let seen   = ref [] in
    let c      = ref c_clause in
    let tr_ind = ref (Vec.size env.trail - 1) in
    let size   = ref 1 in
    let history = ref [] in
    while !cond do
      if !c.learnt then clause_bump_activity !c;
      history := !c :: !history;
    (* visit the current predecessors *)
      for j = 0 to Vec.size !c.atoms - 1 do
        let q = Vec.get !c.atoms j in
      (*printf "I visit %a@." D1.atom q;*)
        assert (q.is_true || q.neg.is_true && q.var.level >= 0); (* Pas sur *)
        if not q.var.seen && q.var.level > 0 then begin
        (*(try
          fprintf fmt "%a -> %f@."
          Types.pr_atom q q.var.weight;
          var_bump_activity q.var;
          with Not_found ->
          fprintf fmt "%a -> %f NOT found@."
          Types.pr_atom q q.var.weight;
          assert false
          );*)
          q.var.seen <- true;
          seen := q :: !seen;
          if q.var.level >= max_lvl then incr pathC
          else begin
            learnt := q :: !learnt; 
            incr size;
            blevel := max !blevel q.var.level
          end
        end
      done;
      
    (* look for the next node to expand *)
      while not (Vec.get env.trail !tr_ind).var.seen do decr tr_ind done;
      decr pathC;
      let p = Vec.get env.trail !tr_ind in
      decr tr_ind;
      match !pathC, p.var.reason with
        | 0, _ -> 
          cond := false;
          learnt := p.neg :: (List.rev !learnt)
        | n, None   -> assert false
        | n, Some cl -> c := cl
    done;
    List.iter (fun q -> q.var.seen <- false) !seen;
    !blevel, !learnt, !history, !size



  let add_boolean_conflict confl =
    env.conflicts <- env.conflicts + 1;
    if decision_level() = 0 then report_b_unsat confl; (* Top-level conflict *)
    let blevel, learnt, history, size = analyze confl in
    cancel_until blevel;
    record_learnt_clause blevel learnt history size


  exception TopClause
  exception BotClause

  let partial_model () = 
    Options.partial_bmodel () &&
      try
        for i = 0 to Vec.size env.clauses - 1 do
          let c = Vec.get env.clauses i in
          try
            for j = 0 to Vec.size c.atoms - 1 do
              if (Vec.get c.atoms j).is_true then raise TopClause
            done;
            raise BotClause
          with TopClause -> ()
        done;
        true
      with BotClause -> false

  let search n_of_conflicts n_of_learnts = 
    let conflictC = ref 0 in
    env.starts <- env.starts + 1;
    while (true) do
      match propagate () with
        | Some confl -> (* Conflict *)
          incr conflictC;
	  add_boolean_conflict confl
            
        | None -> (* No Conflict *)
	  match theory_propagate () with
	    | Some dep -> 
	      incr conflictC;
	      env.conflicts <- env.conflicts + 1;
	      if decision_level() = 0 then report_t_unsat dep; 
                (* T-L conflict *)

	      let blevel, learnt, history, size = theory_analyze dep in
	      cancel_until blevel;
	      record_learnt_clause blevel learnt history size
		
	    | None -> 
	      if nb_assigns () = env.nb_init_vars || partial_model ()
              then raise Sat;
	      if n_of_conflicts >= 0 && !conflictC >= n_of_conflicts then 
		begin
		  env.progress_estimate <- progress_estimate();
		  cancel_until 0;
		  raise Restart
		end;
	      if decision_level() = 0 then simplify ();
	      
	      if n_of_learnts >= 0 && 
		Vec.size env.learnts - nb_assigns() >= n_of_learnts then 
		reduce_db();
	      
	      env.decisions <- env.decisions + 1;
	      new_decision_level();
	      let next = pick_branch_lit () in
	      let current_level = decision_level () in
	      assert (next.var.level < 0);
		(* eprintf "decide: %a@." Types.pr_atom next; *)
	      enqueue next current_level None
    done

  let check_clause c = 
    let b = ref false in
    let atoms = c.atoms in
    for i = 0 to Vec.size atoms - 1 do
      let a = Vec.get atoms i in
      b := !b || a.is_true
    done;
    assert (!b)
      
  let check_vec vec = 
    for i = 0 to Vec.size vec - 1 do check_clause (Vec.get vec i) done
      
  let check_model () = 
    check_vec env.clauses;
    check_vec env.learnts


  let solve () = 
    if env.is_unsat then raise (Unsat env.unsat_core);
    let n_of_conflicts = ref (to_float env.restart_first) in
    let n_of_learnts = ref ((to_float (nb_clauses())) *. env.learntsize_factor) in
    try
      while true do
        (try search (to_int !n_of_conflicts) (to_int !n_of_learnts);
         with Restart -> ());
        n_of_conflicts := !n_of_conflicts *. env.restart_inc;
        n_of_learnts   := !n_of_learnts *. env.learntsize_inc;
      done;
    with 
      | Sat -> 
        (*check_model ();*)
        raise Sat
      | (Unsat cl) as e -> 
        (* check_unsat_core cl; *)
        raise e

  exception Trivial

  let partition atoms init =
    let rec partition_aux trues unassigned falses init = function
      | [] -> trues @ unassigned @ falses, init
      | a::r -> 
        if a.is_true then 
	  if a.var.level = 0 then raise Trivial
	  else (a::trues) @ unassigned @ falses @ r, init
        else if a.neg.is_true then
	  if a.var.level = 0 then 
	    partition_aux trues unassigned falses 
	      (List.rev_append (a.var.vpremise) init) r
	  else partition_aux trues unassigned (a::falses) init r
        else partition_aux trues (a::unassigned) falses init r
    in
    partition_aux [] [] [] init atoms


  let add_clause f ~cnumber atoms =
    if env.is_unsat then raise (Unsat env.unsat_core);
  (*if not (clause_exists atoms) then XXX TODO *)
    let init_name = string_of_int cnumber in
    let init0 = 
      make_clause init_name atoms f (List.length atoms) false [] in
    try
      let atoms, init = 
        if decision_level () = 0 then
	  let atoms, init = List.fold_left
	    (fun (atoms, init) a -> 
	      if a.is_true then raise Trivial;
	      if a.neg.is_true then 
	        atoms, (List.rev_append (a.var.vpremise) init)
	      else a::atoms, init
	    ) ([], [init0]) atoms in
	  List.fast_sort (fun a b -> a.var.vid - b.var.vid) atoms, init
        else partition atoms [init0]
      in
      let size = List.length atoms in
      match atoms with
        | [] -> 
          report_b_unsat init0;
          
        | a::_::_ -> 
          let name = fresh_name () in
          let clause = make_clause name atoms vraie_form size false init in
          attach_clause clause;
          Vec.push env.clauses clause;
          if debug_sat () && verbose () then
            fprintf fmt "[satML] add_clause: %a@." Types.pr_clause clause;
	  
	  if a.neg.is_true then begin
	    let lvl = List.fold_left (fun m a -> max m a.var.level) 0 atoms in
	    cancel_until lvl;
	    add_boolean_conflict clause
	  end
            
        | [a]   ->
          if debug_sat () && verbose () then
            fprintf fmt "[satML] add_atom: %a@." Types.pr_atom a;

          cancel_until 0;
          a.var.vpremise <- init;
          enqueue a 0 None;
          match propagate () with 
              None -> () | Some confl -> report_b_unsat confl
    with Trivial -> ()

  let add_clauses cnf f ~cnumber = 
    List.iter (add_clause f ~cnumber) cnf;
    match theory_propagate () with
        None -> () | Some dep -> report_t_unsat dep
          
  let init_solver cnf f ~cnumber =
    let nbv, _ = made_vars_info () in
    let nbc = env.nb_init_clauses + List.length cnf in
    Vec.grow_to_by_double env.vars nbv;
    Iheap.grow_to_by_double env.order nbv;
    List.iter 
      (List.iter 
         (fun a ->
	   Vec.set env.vars a.var.vid a.var;
	   insert_var_order a.var
         )
      ) cnf;
    env.nb_init_vars <- nbv;
    Vec.grow_to_by_double env.model nbv;
    Vec.grow_to_by_double env.clauses nbc;
    Vec.grow_to_by_double env.learnts nbc;
    env.nb_init_clauses <- nbc;
    add_clauses cnf f ~cnumber


  let assume cnf f ~cnumber =
    match cnf with
      | [] -> ()
      | _ ->
      (*let cnf = List.map (List.map Solver_types.add_atom) cnf in*)
        init_solver cnf f ~cnumber;
        if verbose () then  begin
          fprintf fmt "%d clauses@." (Vec.size env.clauses);
          fprintf fmt "%d learnts@." (Vec.size env.learnts);
        end

  let boolean_model () = 
    let l = ref [] in
    for i = Vec.size env.trail - 1 downto 0 do
      l := (Vec.get env.trail i) :: !l
    done;
    !l

  let current_tbox () = env.tenv

  let empty () = 
    for i = 0 to Vec.size env.vars - 1 do
      try 
        let var = Vec.get env.vars i in
        var.pa.is_true <- false;
        var.na.is_true <- false;
        var.level <- -1;
        var.index <- -1;
        var.reason <- None;
        var.vpremise <- [];
      with Not_found -> ()
    done;
    env.is_unsat <- false;
    env.unsat_core <- [];
    env.clauses <- Vec.make 0 dummy_clause; 
    env.learnts <- Vec.make 0 dummy_clause; 
    env.clause_inc <- 1.;
    env.var_inc <- 1.;
    env.vars <- Vec.make 0 dummy_var; 
    env.qhead <- 0;
    env.simpDB_assigns <- -1;
    env.simpDB_props <- 0;
    env.order <- Iheap.init 0; (* sera mis a jour dans solve *)
    env.progress_estimate <- 0.;
    env.restart_first <- 100;
    env.starts <- 0;
    env.decisions <- 0;
    env.propagations <- 0;
    env.conflicts <- 0;
    env.clauses_literals <- 0;
    env.learnts_literals <- 0;
    env.max_literals <- 0;
    env.tot_literals <- 0;
    env.nb_init_vars <- 0;
    env.nb_init_clauses <- 0;
    env.tenv <- (Th.empty ());
    env.model <- Vec.make 0 dummy_var;
    env.trail <- Vec.make 601 dummy_atom;
    env.trail_lim <- Vec.make 601 (-105);
    env.tenv_queue <- Vec.make 100 (Th.empty ());
    env.tatoms_queue <- Queue.create ()

  let clear () =
    empty ();
    Solver_types.clear ()


  let copy (v : 'a) : 'a = Marshal.from_string (Marshal.to_string v []) 0

  let save () =
    let sv =
      { env = env;
        st_cpt_mk_var = !Solver_types.cpt_mk_var;
        st_ma = !Solver_types.ma }
    in
    copy sv

  let restore { env = s_env; st_cpt_mk_var = st_cpt_mk_var; st_ma = st_ma } =
    env.is_unsat <- s_env.is_unsat;
    env.unsat_core <- s_env.unsat_core;
    env.clauses <- s_env.clauses;
    env.learnts <- s_env.learnts;
    env.clause_inc <- s_env.clause_inc;
    env.var_inc <- s_env.var_inc;
    env.vars <- s_env.vars;
    env.qhead <- s_env.qhead;
    env.simpDB_assigns <- s_env.simpDB_assigns;
    env.simpDB_props <- s_env.simpDB_props;
    env.order <- s_env.order;
    env.progress_estimate <- s_env.progress_estimate;
    env.restart_first <- s_env.restart_first;
    env.starts <- s_env.starts;
    env.decisions <- s_env.decisions;
    env.propagations <- s_env.propagations;
    env.conflicts <- s_env.conflicts;
    env.clauses_literals <- s_env.clauses_literals;
    env.learnts_literals <- s_env.learnts_literals;
    env.max_literals <- s_env.max_literals;
    env.tot_literals <- s_env.tot_literals;
    env.nb_init_vars <- s_env.nb_init_vars;
    env.nb_init_clauses <- s_env.nb_init_clauses;
    env.tenv <- s_env.tenv;
    env.model <- s_env.model;
    env.trail <- s_env.trail;
    env.trail_lim <- s_env.trail_lim;
    env.tenv_queue <- s_env.tenv_queue;
    env.tatoms_queue <- s_env.tatoms_queue;
    env.learntsize_factor <- s_env.learntsize_factor;
    Solver_types.cpt_mk_var := st_cpt_mk_var;
    Solver_types.ma := st_ma


(*end*)
end
