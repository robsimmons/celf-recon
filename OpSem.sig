(*  Celf
 *  Copyright (C) 2008 Anders Schack-Nielsen and Carsten Sch�rmann
 *
 *  This file is part of Celf.
 *
 *  Celf is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Celf is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Celf.  If not, see <http://www.gnu.org/licenses/>.
 *)

signature OPSEM =
sig

val traceSolve : int ref
val debugForwardChaining : bool ref
val allowConstr : bool ref
val fcLimit : int option ref

type context
type lcontext

(* solve looks for proofs of |- A true
     - the context object (lcontext * context)
     - the type being searched for/goal 
     - the success continuation? - rjs march 8 2012 *)
val solve : (lcontext * context) * Syntax.asyncType * (Syntax.obj * context -> unit) -> unit

val solveEC : Syntax.asyncType * (Syntax.obj -> unit) -> unit

(* Pretty-print the intermediate contexts *)
val printCtx : lcontext * context -> unit

(* Runs the trace, optionally printing out intermediate steps *)
val trace : bool -> int option -> Syntax.syncType -> int * (lcontext * context)

end
