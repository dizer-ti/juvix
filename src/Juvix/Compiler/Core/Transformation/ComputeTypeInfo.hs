module Juvix.Compiler.Core.Transformation.ComputeTypeInfo where

import Juvix.Compiler.Core.Data.BinderList qualified as BL
import Juvix.Compiler.Core.Extra
import Juvix.Compiler.Core.Info.TypeInfo qualified as Info
import Juvix.Compiler.Core.Transformation.Base

computeNodeType' :: Module -> BinderList Binder -> Node -> Type
computeNodeType' md bl node = rePis argtys' ty'
  where
    ty = computeNodeType md (mkLambdas'' (reverse (toList bl)) node)
    (argtys, ty') = unfoldPi ty
    argtys' = drop (length bl) argtys

-- | Computes the type of a closed well-typed node.
computeNodeType :: Module -> Node -> Type
computeNodeType md = Info.getNodeType . computeNodeTypeInfo md

-- | Computes the TypeInfo for each subnode of a well-typed node.
--
-- Assumptions:
-- 1. The node is well-typed.
-- 2. All binders and identifiers are decorated with correct full type
--    information.
-- 3. All cases have at least one branch.
-- 4. No `Match` nodes.
-- 5. All inductives and function types are in universe 0.
computeNodeTypeInfo :: Module -> Node -> Node
computeNodeTypeInfo md = umapL go
  where
    go :: BinderList Binder -> Node -> Node
    go bl node = Info.setNodeType (nodeType bl node) node

    nodeType :: BinderList Binder -> Node -> Type
    nodeType bl node = case node of
      NVar Var {..} ->
        shift (_varIndex + 1) (BL.lookup _varIndex bl ^. binderType)
      NIdt Ident {..} ->
        lookupIdentifierInfo md _identSymbol ^. identifierType
      NCst Constant {..} ->
        case _constantValue of
          ConstInteger {} -> mkTypeInteger'
          ConstField {} -> mkTypeField'
          ConstString {} -> mkTypeString'
          ConstUInt8 {} -> mkTypeUInt8'
          ConstByteArray {} -> mkDynamic'
      NApp {} ->
        let (fn, args) = unfoldApps' node
            fty = Info.getNodeType fn
            (tyargs, target) = unfoldPi fty
            target' = rePis (drop (length args) tyargs) target
         in substs (reverse args) target'
      NBlt BuiltinApp {..} ->
        case _builtinAppOp of
          OpIntAdd -> mkTypeInteger'
          OpIntSub -> mkTypeInteger'
          OpIntMul -> mkTypeInteger'
          OpIntDiv -> mkTypeInteger'
          OpIntMod -> mkTypeInteger'
          OpIntLt -> mkTypeBool'
          OpIntLe -> mkTypeBool'
          OpFieldAdd -> mkTypeField'
          OpFieldSub -> mkTypeField'
          OpFieldMul -> mkTypeField'
          OpFieldDiv -> mkTypeField'
          OpFieldFromInt -> mkTypeField'
          OpFieldToInt -> mkTypeInteger'
          OpEq -> mkTypeBool'
          OpShow -> mkTypeString'
          OpStrConcat -> mkTypeString'
          OpStrToInt -> mkTypeInteger'
          OpSeq -> case _builtinAppArgs of
            [_, arg2] -> Info.getNodeType arg2
            _ -> error "incorrect seq builtin application"
          OpAssert -> case _builtinAppArgs of
            [arg] -> Info.getNodeType arg
            _ -> error "incorrect assert builtin application"
          OpRangeCheck -> mkTypeBool'
          OpTrace -> case _builtinAppArgs of
            [arg] -> Info.getNodeType arg
            _ -> error "incorrect trace builtin application"
          OpFail -> Info.getNodeType node
          OpNockmaReify -> Info.getNodeType node
          OpAnomaGet -> Info.getNodeType node
          OpAnomaEncode -> Info.getNodeType node
          OpAnomaDecode -> Info.getNodeType node
          OpAnomaVerifyDetached -> Info.getNodeType node
          OpAnomaSign -> Info.getNodeType node
          OpAnomaSignDetached -> Info.getNodeType node
          OpAnomaVerifyWithMessage -> Info.getNodeType node
          OpAnomaByteArrayFromAnomaContents -> Info.getNodeType node
          OpAnomaByteArrayToAnomaContents -> mkTypeInteger'
          OpAnomaSha256 -> mkTypeByteArray'
          OpAnomaResourceCommitment -> mkTypeInteger'
          OpAnomaResourceNullifier -> mkTypeInteger'
          OpAnomaResourceKind -> mkDynamic'
          OpAnomaResourceDelta -> mkDynamic'
          OpAnomaActionDelta -> mkDynamic'
          OpAnomaActionsDelta -> mkDynamic'
          OpAnomaZeroDelta -> mkDynamic'
          OpAnomaAddDelta -> mkDynamic'
          OpAnomaSubDelta -> mkDynamic'
          OpAnomaRandomGeneratorInit -> mkTypeRandomGenerator'
          OpAnomaRandomNextBytes -> mkDynamic'
          OpAnomaRandomSplit -> mkDynamic'
          OpAnomaIsCommitment -> mkTypeBool'
          OpAnomaIsNullifier -> mkTypeBool'
          OpAnomaCreateFromComplianceInputs -> mkDynamic'
          OpAnomaProveDelta -> mkDynamic'
          OpAnomaActionCreate -> mkDynamic'
          OpAnomaTransactionCompose -> mkDynamic'
          OpAnomaSetToList -> mkDynamic'
          OpAnomaSetFromList -> mkDynamic'
          OpPoseidonHash -> case _builtinAppArgs of
            [arg] -> Info.getNodeType arg
            _ -> error "incorrect poseidon builtin application"
          OpEc -> case _builtinAppArgs of
            [arg, _, _] -> Info.getNodeType arg
            _ -> error "incorrect ec_op builtin application"
          OpRandomEcPoint -> case _builtinAppArgs of
            [] -> mkDynamic'
            _ -> error "incorrect random_ec_point builtin application"
          OpUInt8ToInt -> mkTypeInteger'
          OpUInt8FromInt -> mkTypeUInt8'
          OpByteArrayFromListByte -> mkDynamic'
          OpByteArrayLength -> mkTypeInteger'
      NCtr Constr {..} ->
        let ci = lookupConstructorInfo md _constrTag
            ii = lookupInductiveInfo md (ci ^. constructorInductive)
         in case ii ^. inductiveBuiltin of
              Just (BuiltinTypeInductive BuiltinBool) ->
                mkTypeBool'
              _ ->
                mkTypeConstr' (ci ^. constructorInductive) (take (length (ii ^. inductiveParams)) _constrArgs)
      NLam Lambda {..} ->
        mkPi mempty _lambdaBinder (Info.getNodeType _lambdaBody)
      NLet Let {..} ->
        let bodyTy = Info.getNodeType _letBody
         in subst (_letItem ^. letItemValue) bodyTy
      NRec {} -> error "letrec unsupported"
      NCase Case {..} -> case _caseDefault of
        Just nd -> Info.getNodeType nd
        Nothing -> case _caseBranches of
          CaseBranch {..} : _ ->
            shift (-_caseBranchBindersNum) (Info.getNodeType _caseBranchBody)
          [] -> error "case with no branches"
      NMatch Match {} ->
        error "match unsupported"
      NPi Pi {} ->
        mkUniv' 0
      NUniv Univ {..} ->
        mkUniv' (_univLevel + 1)
      NTyp TypeConstr {} ->
        mkUniv' 0
      NPrim TypePrim {} ->
        mkUniv' 0
      NDyn DynamicTy {} ->
        mkUniv' 0
      NBot Bottom {..} ->
        _bottomType
      Closure {} ->
        impossible

computeTypeInfo :: Module -> Module
computeTypeInfo md = mapT (const (computeNodeTypeInfo md)) md
