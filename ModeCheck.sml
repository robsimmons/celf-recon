structure ModeCheck :> MODECHECK =
struct

open Syntax
open Context
open PatternNormalize
structure RAList = RandomAccessList

exception ModeCheckError of string


(* Variable status:
   - Ground:    an existential variable that is known to be ground
   - Unknown:   an existential variable that is not known yet if it is ground
   - Universal: a universal variable (can be treated as a constant)
*)

datatype status = Ground
                | Unknown
                | Universal

(* A groundness context is a list indicating the groundness status of bound
   variables and a boolean indicating an obligation to be ground *)
type mcontext = (string * modality * (status * bool)) RAList.ralist

(* status has the following join and meet (partial) operations *)
fun stJoin (Unknown,_) = Unknown
  | stJoin (_,Unknown) = Unknown
  | stJoin (Ground,Ground) = Ground
  | stJoin (Universal,Universal) = Universal
  | stJoin (_,_) = raise Fail "Internal error: status Join"

fun stMeet (Ground,_) = Ground
  | stMeet (_,Ground) = Ground
  | stMeet (Unknown,Unknown) = Unknown
  | stMeet (Universal,Universal) = Universal
  | stMeet (_,_) = raise Fail "Internal error: status Join"

(* a pair (variable status, ground obligation) has the following join and
   meet operations *)
fun varJoin ((st1,g1),(st2,g2)) = (stJoin (st1,st2),g1 andalso g2)
fun varMeet ((st1,g1),(st2,g2)) = (stMeet (st1,st2),g1 orelse g2)

(* the above operations extend to mcontexts of a given length *)
(* TODO: implement more efficient version *)
fun mcJoin x =
  RAList.pairMapEq (fn ((x, m, st1), (_, _, st2)) => (x, m, varJoin (st1, st2))) x
fun mcMeet x =
  RAList.pairMapEq (fn ((x, m, st1), (_, _, st2)) => (x, m, varMeet (st1, st2))) x

(* mctxPush : string * modality -> status -> mcontext -> mcontext *)
fun mctxPush (x, m) st ctx = RAList.cons (x, m, (st, false)) ctx

(* mctxPushNO : mcontext -> mcontext *)
fun mctxPushNO ctx = mctxPush ("", INT) Universal ctx

(* mctxPushNON : int -> mcontext -> mcontext *)
fun mctxPushNON 0 = (fn x => x)
  | mctxPushNON n = mctxPushNO o mctxPushNON (n - 1)

(* mctxPop : mcontext -> mcontext *)
fun mctxPop ctx =
      RAList.tail ctx

(* mctxPopN : int -> mcontext -> mcontext *)
fun mctxPopN 0 = (fn x => x)
  | mctxPopN n = mctxPop o mctxPopN (n - 1)

(* getModality : mcontext * int -> modality *)
fun getModality (ctx, k) = let val (_, m, (_, _)) = RAList.lookup ctx (k-1)
                           in
                               m
                           end

(* getStatus : mcontext * int -> mode *)
fun getStatus (ctx, k) = let val (_, _, (st, _)) = RAList.lookup ctx (k-1)
                         in
                             st
                         end

(* isUniversal : mcontext * int -> bool *)
fun isUniversal (ctx, k) = let val (_, _, (st, _)) = RAList.lookup ctx (k-1)
                           in
                               case st of
                                   Universal => true
                                 | _ => false
                           end



(* pushTPattern : status -> (mcontext * tpattern) -> (mcontext, int)
   pushTPattern st (ctx, p) = (ctx', k)
   iff  ctx' is obtained by adding the variables in p to ctx with status st
        k    is the number of added patterns *)
fun pushTPattern st (ctx, p) =
    let fun patNameModality p =
            case Pattern.prj p of
                PDown _ => ("", LIN)
              | PAffi _ => ("", AFF)
              | PBang x => (getOpt (x, ""), INT)
              | _ => raise Fail "Internal error: patNameModality on tpattern PDepTensor"
        fun pushTPattern_ (ctx, p) =
            case Pattern.prj p of
                POne => (ctx, 0)
              | PDepTensor (p1, p2) =>
                let
                  val (ctx1, n1) = pushTPattern_ (ctx, p1)
                  val (ctx2, n2) = pushTPattern_ (ctx1, p2)
                in
                  (ctx2, n1 + n2)
                end
              | _ => (* PDown, PAffi, PBang *)
                (mctxPush (patNameModality p) st ctx, 1)
    in
        pushTPattern_ (ctx, p)
    end

(* pushOPattern : status -> (mcontext * opattern) -> (mcontext, int)
   pushOPattern st (ctx, p) = (ctx', k)
   iff  ctx' is obtained by adding the variables in p to ctx with status st
        k    is the number of added patterns *)
fun pushOPattern st (ctx, p) =
    let fun patNameModality p =
            case Pattern.prj p of
                PDown x => (x, LIN)
              | PAffi x => (x, AFF)
              | PBang x => (x, INT)
              | _ => raise Fail "Internal error: patName: pattern not normalized"
        fun pushOPattern_ (ctx, p) =
            case Pattern.prj p of
                POne => (ctx, 0)
              | PDepTensor (p1, p2) =>
                let
                  val (ctx1, n1) = pushOPattern_ (ctx, p1)
                  val (ctx2, n2) = pushOPattern_ (ctx1, p2)
                in
                  (ctx2, n1 + n2)
                end
              | _ => (* PDown, PAffi, PBang *)
                (mctxPush (patNameModality p) st ctx, 1)
    in
        pushOPattern_ (ctx, p)
    end


(* Check groundness information for objects *)
(* gCheck* : mcontext * object -> unit *)
(* gCheck* (ctx, ob) raises ModeCheckError if

      exists k. k \in FV(ob) /\ lookup (ctx, k-1) = (_, (Unknown, _))

   or returns () if no such k exists.
 *)
fun gCheckObj (ctx, ob) =
    case NfObj.prj ob of
        NfLLam (p, N) => gCheckObj (#1 (pushOPattern Universal (ctx, opatNormalize p)), N)
      | NfAddPair (N1, N2) => (gCheckObj (ctx, N1); gCheckObj (ctx, N2))
      | NfMonad E => gCheckExpObj (ctx, E)
      | NfAtomic (H, S) => (case H of
                                Const x => gCheckSpine (ctx, S)
                              | Var (_, n) => let val (x, _, (st, _)) = RAList.lookup ctx (n-1)
                                              in
                                                  case st of
                                                      Unknown => raise ModeCheckError (x^" not necessarily ground11")
                                                    | _ => gCheckSpine (ctx, S)
                                              end
                              | UCVar _ => raise Fail "Internal error: gCheckObj on UCVar"
                              | LogicVar _ => raise Fail "Internal error: gCheckObj on LogicVar")

and gCheckExpObj (ctx, ob) =
    case NfExpObj.prj ob of
        NfLet (p, (H, S), E)
        => (case H of
                Const x => (gCheckSpine (ctx, S);
                            gCheckExpObj (#1 (pushOPattern Universal (ctx, opatNormalize p)), E))
              | Var (_,n) => let val (x, _, (st, _)) = RAList.lookup ctx (n-1)
                             in
                                 case st of
                                     Unknown => raise ModeCheckError (x^" not necessarily ground2")
                                   | _ => gCheckSpine (ctx, S)
                             end
              | UCVar _ => raise Fail "Internal error: gCheckExpObj on UCVar"
              | LogicVar _ => raise Fail "Internal error: gCheckExpObj on LogicVar")
      | NfMon M => gCheckMonadObj (ctx, M)

and gCheckMonadObj (ctx, ob) =
    case NfMonadObj.prj ob of
        DepPair (M1, M2) => (gCheckMonadObj (ctx, M1); gCheckMonadObj (ctx, M2))
      | One => ()
      | Down N => gCheckObj (ctx, N)
      | Affi N => gCheckObj (ctx, N)
      | Bang N => gCheckObj (ctx, N)
      | MonUndef => raise Fail "Internal error: gCheckMonadObj on MonUndef"


and gCheckSpine (ctx, ob) =
    case NfSpine.prj ob of
        Nil => ()
      | LApp (M, S) => (gCheckMonadObj (ctx, M); gCheckSpine (ctx, S))
      | ProjLeft S => gCheckSpine (ctx, S)
      | ProjRight S => gCheckSpine (ctx, S)

(* Infer groundness information for objects *)
(* gInfer* : mcontext * object -> mcontext *)
(* These functions satisfy the following property:

      gInfer* (ctx, ob) = ctx'

      lookup (ctx, k-1) = (x, (Unknown, b)) /\ k \in FV(ob)
            ==> lookup (ctx',k-1) = (x, (Ground, b))
 *)
(* The implementation of gInfer* and associated functions below
   is based on the Twelf implementation *)


(* mkGround : mcontext -> int -> mcontext *)
fun mkGround ctx n =
    let val (x, m, (st, oblig)) = RAList.lookup ctx (n-1)
    in
      case st of
        Unknown => RAList.update ctx (n-1) (x, m, (Ground, oblig))
      | _ => ctx
    end

(* unique (k, ks) = B

   Invariant:
   B iff k does not occur in ks
 *)
fun unique (k:int, nil) = true
  | unique (k, k'::ks) = (k <> k') andalso unique (k, ks)

exception Eta

(* isPattern : mcontext * int * spine -> bool

   isPattern (D, k, mS) = B

   Invariant:
   B iff k > k' for all k' in mS
         and for all k in mS: k is parameter
         and for all k', k'' in mS: k' <> k''
 *)
fun checkPattern (ctx, k, args, sp) =
    let fun checkPatternObj (ctx, k, args, ob, m, sp) =
            let
	        val (_, k') = Eta.etaContract Eta ob
            in
	        if (k > k')
                   andalso isUniversal (ctx, k')
	           andalso unique (k', args)
                   (* The next line disallows linear-changing pattern substitutions *)
                   (* andalso getModality (ctx, k') = m *)
	        then checkPattern (ctx, k, k'::args, sp)
	        else raise Eta
            end
    in
        case NfSpine.prj sp of
            Nil => ()
          | LApp (M, S) =>
            (case NfMonadObj.prj M of
                 DepPair _ => raise Eta
               | One => checkPattern (ctx, k, args, S)
               | Down N => checkPatternObj (ctx, k, args, N, LIN, S)
               | Affi N => checkPatternObj (ctx, k, args, N, AFF, S)
               | Bang N => checkPatternObj (ctx, k, args, N, INT, S)
               | MonUndef => raise Fail "Internal error: checkPattern on MonUndef")
          | ProjLeft S => checkPattern (ctx, k, args, S)
          | ProjRight S => checkPattern (ctx, k, args, S)
    end

fun isPattern (ctx, k, S) =
    (checkPattern (ctx, k, nil, S); true)
    handle Eta => false

fun gInferObj (ctx, ob) =
    case NfObj.prj ob of
        NfLLam (p, N) => let val (ctx', k) = pushOPattern Universal (ctx, opatNormalize p)
                         in
                             RAList.drop (gInferObj (ctx', N)) k
                         end
      | NfAddPair (N1, N2) => mcMeet (gInferObj (ctx, N1), gInferObj (ctx, N2))
      | NfMonad E => ctx (* Monadic objects are ignored for the moment -- js *)
      | NfAtomic (H, S) => (case H of
                              Const x => gInferSpine (ctx, S)
                            | Var (_, n) => if isUniversal (ctx, n)
                                            then gInferSpine (ctx, S)
                                            else if isPattern (ctx, n, S)
                                                 then mkGround ctx n
                                                 else ctx
                            | UCVar _ => raise Fail "Internal error: gInferObj on UCVar"
                            | LogicVar _ => raise Fail "Internal error: gInferObj on LogicVar")

and gInferMonadObj (ctx, ob) =
    case NfMonadObj.prj ob of
        DepPair (M1, M2) => mcMeet (gInferMonadObj (ctx, M1), gInferMonadObj (ctx, M2))
      | One => ctx
      | Down N => gInferObj (ctx, N)
      | Affi N => gInferObj (ctx, N)
      | Bang N => gInferObj (ctx, N)
      | MonUndef => raise Fail "Internal error: gInferMonadObj on MonUndef"

and gInferSpine (ctx, sp) =
    case NfSpine.prj sp of
        Nil => ctx
      | LApp (M, S) => mcMeet (gInferMonadObj (ctx, M), gInferSpine (ctx, S))
      | ProjLeft S => gInferSpine (ctx, S)
      | ProjRight S => gInferSpine (ctx, S)

(* Monadic expressions are ignored for the moment *)
and gInferExpObj (ctx, ob) =
    case NfExpObj.prj ob of
        NfLet (p, (H, S), E)
        => (case H of
                Const x => let val ctx' = gInferSpine (ctx, S)
                               val (ctx'', k) = pushOPattern Universal (ctx', opatNormalize p)
                           in
                               RAList.drop (gInferExpObj (ctx'', E)) k
                           end
              | Var (_, n) => (case getStatus (ctx, n) of
                                   Universal => let val ctx' = gInferSpine (ctx, S)
                                                    val (ctx'', k) = pushOPattern Universal (ctx', opatNormalize p)
                                                in
                                                    RAList.drop (gInferExpObj (ctx'', E)) k
                                                end
                                 | Ground    => let val patMode = (gCheckSpine (ctx, S); Ground)
                                                                  handle ModeCheckError _ => Unknown
                                                    val (ctx', k) = pushOPattern patMode (ctx, opatNormalize p)
                                                in
                                                    RAList.drop (gInferExpObj (ctx', E)) k
                                                end
                                 | Unknown   => let val (ctx', k) = pushOPattern Unknown (ctx, opatNormalize p)
                                                in
                                                    RAList.drop (gInferExpObj (ctx', E)) k
                                                end)
              | UCVar _ => raise Fail "Internal error: gInferExpObj on UCVar"
              | LogicVar _ => raise Fail "Internal error: gInferExpObj on LogicVar")
      | NfMon M => gInferMonadObj (ctx, M)

(* Request groundness obligation for objects *)
(* gOblig* : mcontext * object -> mcontext *)
(* These functions satisfy the following property:

      gOblig* (ctx, ob) = ctx'

      lookup (ctx, k-1) = (x, (st, b)) /\ k \in FV(ob)
            ==> lookup (ctx',k-1) = (x, (st, true)), for st = Unknown,Ground

 *)

(* addOblig : mcontext -> int -> mcontext *)
fun addOblig ctx n = let val (x, m, (st, oblig)) = RAList.lookup ctx (n-1)
                     in
                         case st of
                             Universal => ctx
                           | _ => RAList.update ctx (n-1) (x, m, (st, true))
                     end


fun gObligObj (ctx, ob) =
    case NfObj.prj ob of
        NfLLam (p, N) => let val (ctx', k) = pushOPattern Universal (ctx, opatNormalize p)
                         in
                             RAList.drop (gObligObj (ctx', N)) k
                         end
      | NfAddPair (N1, N2) => mcMeet (gObligObj (ctx, N1), gObligObj (ctx, N2))
      | NfMonad E => gObligExpObj (ctx, E)
      | NfAtomic (H, S) => (case H of
                                Const x => gObligSpine (ctx, S)
                              | Var (_, n) => gObligSpine (addOblig ctx n, S)
                              | UCVar _ => raise Fail "Internal error: gObligObj on UCVar"
                              | LogicVar _ => raise Fail "Internal error: gObligObj on LogicVar")

and gObligExpObj (ctx, ob) =
    case NfExpObj.prj ob of
        NfLet (p, (H, S), E)
        => (case H of
                Const x => let val ctx' = gObligSpine (ctx, S)
                               val (ctx'', k) = pushOPattern Universal (ctx', opatNormalize p)
                           in
                               RAList.drop (gObligExpObj (ctx'', E)) k
                           end
              | Var (_,n) => let val ctx' = gObligSpine (addOblig ctx n, S)
                                 val (ctx'', k) = pushOPattern Universal (ctx', opatNormalize p)
                             in
                                 RAList.drop (gObligExpObj (ctx'', E)) k
                             end
              | UCVar _ => raise Fail "Internal error: gObligExpObj on UCVar"
              | LogicVar _ => raise Fail "Internal error: gObligExpObj on LogicVar")
      | NfMon M => gObligMonadObj (ctx, M)

and gObligMonadObj (ctx, ob) =
    case NfMonadObj.prj ob of
        DepPair (M1, M2) => mcMeet (gObligMonadObj (ctx, M1), gObligMonadObj (ctx, M2))
      | One => ctx
      | Down N => gObligObj (ctx, N)
      | Affi N => gObligObj (ctx, N)
      | Bang N => gObligObj (ctx, N)
      | MonUndef => raise Fail "Internal error: gObligMonadObj on MonUndef"


and gObligSpine (ctx, ob) =
    case NfSpine.prj ob of
        Nil => ctx
      | LApp (M, S) => mcMeet (gObligMonadObj (ctx, M), gObligSpine (ctx, S))
      | ProjLeft S => gObligSpine (ctx, S)
      | ProjRight S => gObligSpine (ctx, S)





(* fun bwdHead : mcontext * typeSpine * modeDecl -> mcontext *)
(* bwdHead calls gInfer* for input arguments and gOblig* for output arguments in the spine *)
fun bwdHead (ctx, sp, m) =
    case (NfTypeSpine.prj sp, m) of
        (TNil, []) => ctx
      | (TApp (N,S), (h::t)) => let val ctx' = case h of
                                                   Plus => gInferObj (ctx, N)
                                                 | Minus _ => gObligObj (ctx, N)
                                                 | Star => raise Fail "Internal error: * mode in bwdHead"
                                    val ctx'' = bwdHead (ctx, S, t)
                                in
                                    mcMeet (ctx', ctx'')
                                end
      | _ => raise Fail "Internal error: bwdHead spine and mode declaration length do not coincide"

(* goalAtomic : mcontext * typeSpine * modeDecl -> mcontext *)
(* goalAtomic calls gCheck* for input arguments and gInfer* for output arguments in the spine *)
fun goalAtomic (ctx, sp, m) =
    case (NfTypeSpine.prj sp, m) of
        (TNil, []) => ctx
      | (TApp (N,S), (h::t)) => let val ctx' = case h of
                                                   Plus => (gCheckObj (ctx,N); ctx)
                                                 | Minus _ => gInferObj (ctx, N)
                                                 | Star => raise Fail "Internal error: * mode in goalAtomic"
                                    val ctx'' = goalAtomic (ctx, S, t)
                                in
                                    mcMeet (ctx', ctx'')
                                end
      | _ => raise Fail "Internal error: goalAtomic spine and mode declaration length do not coincide"

(* bwdType : mcontext * nfAsyncType -> mcontext *)
(* Entry point for checking backward-chaining declarations *)
fun bwdType (ctx, ty) =
    case Util.nfTypePrjAbbrev ty of
        TAtomic (a, S) => (case Signatur.getModeDecl a of
                               NONE => raise ModeCheckError ("No mode declaration for "^a)
                             | SOME m => bwdHead (ctx, S, m))
      | AddProd (A1, A2) => let val ctx1 = bwdType (ctx, A1)
                                val ctx2 = bwdType (ctx, A2)
                            in
                                mcJoin (ctx1, ctx2)
                            end
      | TLPi (p, A, B) => let val (p', A') = tpatNormalize (p, A)
                              val len = Syntax.nbinds p'
                          in
                              mctxPopN len (bwdPatTypek ctx 0 (p', A') (fn c => bwdType (c, B)))
                          end
      | TMonad _ =>  raise Fail "Internal error: bwdType on forward goal"
      | TAbbrev _ => raise Fail "Internal error: bwdType on TAbbrev"

(* bwdPatTypek : mcontext -> int * tpattern * nfSyncType * (mcontext -> mcontext) -> mcontext *)
(* bwdPatTypek ctx n (p, sty) k = ctx'
     - size ctx' = size ctx + size p
     - k calls goalType for every non-depenpendt subgoal
     - n is the recursion depth used to calculate shifts
 *)
and bwdPatTypek ctx n (p, sty) k =
    case (Pattern.prj p, NfSyncType.prj sty) of
        (POne, TOne) => k ctx
      | (PDepTensor (p1, p2), LExists (_, S1, S2))
        => (case (Pattern.prj p1, NfSyncType.prj S1) of
                (PBang (SOME x), TBang A)
                => let val ctx' = bwdPatTypek (mctxPush (x, INT) Unknown ctx) (n + 1) (p2, S2) k
                       val (x, _, (st, oblig)) = RAList.lookup ctx' n
                   in
                       if oblig (* x has a groundness obligation *)
                       then case st of
                                Ground => ctx' (* ctxRet *)
                              | Unknown => raise ModeCheckError (x^" not necessarily ground3")
                              | Universal => raise Fail "Internal error: bwdPatTypek: Unknown changed to Univ"
                       else ctx' (* ctxRet *)
                   end
              | (_, _)  (* _ is PDown, PAffi, or PBang NONE, since patterns are normalized *)
                =>
                let
                  fun goalK c =
                      let
                        val ctx1 = k c
                        val ctx2 = goalType (mctxPopN (Syntax.nbinds p) ctx1, sync2async S1)
                      in
                        mctxPushNON (Syntax.nbinds p) ctx2
                      end
                in
                  bwdPatTypek (mctxPushNO ctx) (n + 1) (p2, S2) goalK
                end
           )
      | _ => raise Fail "Internal error: bwdPatTypek: pattern not normalized"

(* fun goalType : mcontext * nfAsyncType -> mcontext *)
and goalType (ctx, ty) =
    case Util.nfTypePrjAbbrev ty of
        TAtomic (a, S) => (case Signatur.getModeDecl a of
                               NONE => raise ModeCheckError ("No mode declaration for "^a)
                             | SOME m => goalAtomic (ctx, S, m)
                          )
      | AddProd (A1, A2) => goalType (goalType (ctx, A1), A2)
      | TLPi (p, A, B) => let val (p', A') = tpatNormalize (p, A) in
                              goalPatType (ctx, p', A', B)
                          end
      | TMonad S => goalSyncType (ctx, S)
      | TAbbrev _ => raise Fail "Internal error: bwdType on TAbbrev"

(* fun goalSyncType : mcontext * synctType -> mcontext *)
and goalSyncType (ctx, sty) =
    case NfSyncType.prj sty of
        TOne => ctx
      | LExists (p, S1, S2) => let val (p', _) = tpatNormalize (p, S1)
                                   val (ctx', k) = pushTPattern Unknown (ctx, p')
                               in
                                   RAList.drop (goalSyncType (ctx', S2)) k
                               end
      | _ (* TDown, TAffi, TBang *)
        => goalType (ctx, sync2async sty)


(* goalPatType : mcontext * pattern * nfSyncType * nfAsyncType -> mcontext *)
(* Precondition  goalPatType (ctx, p, sty, ty)
      - p must be normalized
      - p and sty must be related
 *)
and goalPatType (ctx, p, sty, ty) =
    case (Pattern.prj p, NfSyncType.prj sty) of
        (POne, TOne) => goalType (ctx, ty)
      | (PDepTensor (p1, p2), LExists (_, S1, S2))
        => (case (Pattern.prj p1, NfSyncType.prj S1) of
                (PBang (SOME x), TBang A) => mctxPop (goalPatType (mctxPush (x, INT) Universal ctx, p2, S2, ty))

              | (_, _) (* _ is PDown, PAffi, or PBang NONE, since patterns are normalized *)
                => (modeCheckDeclInt (ctx, sync2async S1);
                    mctxPop (goalPatType (mctxPushNO ctx, p2, S2, ty))))

      | _ => raise Fail "Internal error: goalPatType: pattern not normalized"


(* fwdType : mcontext * nfAsyncType -> unit *)
(* Entry point for forward-chaining declarations *)
and fwdType (ctx, ty) =
    case Util.nfTypePrjAbbrev ty of
        TLPi (p, A, B) => let val (p', A') = tpatNormalize (p, A) in
                              fwdPatType (ctx, p', A', B)
                          end
      | AddProd (A, B) => (fwdType (ctx, A); fwdType (ctx, B))
      | TMonad S => fwdSyncType (ctx, S)
      | TAtomic _ => raise Fail "Internal error: fwdType on backward goal"
      | TAbbrev _ => raise Fail "Internal error: fwdType on TAbbrev"


(* fwdSyncType : mcontext * nfSyncType -> unit *)
and fwdSyncType (ctx, sty) =
    case NfSyncType.prj sty of
        TOne => ()
      | LExists (p, S1, S2) => let val (p', _) = tpatNormalize (p, S1)
                                   val (ctx', _) = pushTPattern Universal (ctx, p')
                               in
                                   fwdSyncType (ctx', S2)
                               end
      | _ (* TDown, TAffi, TBang *)
        => modeCheckDeclInt (ctx, sync2async sty)


(* fwdPatType : mcontext * tpattern * nfSyncType * nfAsyncType -> unit *)
(* Precondition  fwdPatType (ctx, p, sty, ty)
      - p must be normalized
      - p and sty must be related
 *)
and fwdPatType (ctx, p, sty, ty) =
    case (Pattern.prj p, NfSyncType.prj sty) of
        (POne, TOne) => fwdType (ctx, ty)
      | (PDepTensor (p1, p2), LExists (_, S1, S2))
        => (case (Pattern.prj p1, NfSyncType.prj S1) of
                (PBang (SOME x), TBang A) => fwdPatType (mctxPush (x, INT) Unknown ctx, p2, S2, ty)
              | (_, _) (* _ is PDown, PAffi, or PBang NONE, since patterns are normalized *)
                => fwdPatType (mctxPushNO (goalType (ctx, sync2async S1)), p2, S2, ty))
      | _ => raise Fail "Internal error: fwdPatType: pattern not normalized"


(* modeCheckDeclInt : mcontext * nfAsyncType -> unit *)
(* Main entry point for mode-checking declarations.
   Calls bwdType or fwdType if the declarations is backward-chaining or forward-chaining, resp.
   Returns () if the declaration is mode-correct.
   Raises ModeCheckError otherwise.
 *)
and modeCheckDeclInt (ctx, ty) =
    if GoalMode.isBchain ty
    then let val _ = bwdType (ctx, ty) in () end
    else if GoalMode.isFchain ty
    then fwdType (ctx, ty)
    else raise Fail "Internal error: modeCheckDeclInt on MIXED goal"


(* fun isNeeded : nfAsyncType -> bool *)
fun isNeeded ty =
    let fun isNeededType ty =
            case Util.nfTypePrjAbbrev ty of
                TLPi (p, A, B) => isNeeded B orelse isNeededSyncType A
              | AddProd (A, B) => isNeeded A orelse isNeeded B
              | TMonad A => isNeededSyncType A
              | TAtomic (x, S) => Signatur.hasModeDecl x
              | TAbbrev _ => raise Fail "Internal error: mode checking on TAbbrev"
        and isNeededSyncType sty =
            case NfSyncType.prj sty of
                TOne => false
              | LExists (p, S1, S2) => isNeededSyncType S1 orelse isNeededSyncType S2
              | _ => isNeededType (sync2async sty)
    in
        isNeededType ty
    end


(* modeCheckDecl : nfAsyncType -> unit *)
fun modeCheckDecl ty = modeCheckDeclInt (RAList.empty, ty)

end
