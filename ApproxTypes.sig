signature APPROXTYPES =
sig

val traceApx : bool ref

type context
val emptyCtx : context

exception ExnApxUnifyType of string

val occur : Syntax.typeLogicVar -> Syntax.apxAsyncType -> unit
val apxUnifyType : Syntax.apxAsyncType * Syntax.apxAsyncType -> unit

val pat2apxSyncType : Syntax.pattern -> Syntax.apxSyncType

val apxCheckKind : context * Syntax.kind -> Syntax.kind
val apxCheckType : context * Syntax.asyncType -> Syntax.asyncType
val apxCheckTypeSpine : context * Syntax.typeSpine * Syntax.apxKind -> Syntax.typeSpine
val apxCheckSyncType : context * Syntax.syncType -> Syntax.syncType
val apxCheckObj : context * Syntax.obj * Syntax.apxAsyncType -> context * bool * Syntax.obj
val apxInferObj : context * Syntax.obj -> context * bool * Syntax.obj * Syntax.apxAsyncType
val apxInferExp : context * Syntax.expObj -> context * bool * Syntax.expObj * Syntax.apxSyncType
val apxCheckPattern : context * Syntax.pattern -> Syntax.pattern
val apxInferMonadObj : context * Syntax.monadObj -> context * bool * Syntax.monadObj * Syntax.apxSyncType

val apxCheckKindEC : Syntax.kind -> Syntax.kind
val apxCheckTypeEC : Syntax.asyncType -> Syntax.asyncType
val apxCheckObjEC : Syntax.obj * Syntax.apxAsyncType -> Syntax.obj

end
