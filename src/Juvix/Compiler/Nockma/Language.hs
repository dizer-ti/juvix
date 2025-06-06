module Juvix.Compiler.Nockma.Language
  ( module Juvix.Compiler.Nockma.Language,
    module Juvix.Compiler.Core.Language.Base,
    module Juvix.Compiler.Nockma.AnomaLib.Base,
    module Juvix.Compiler.Nockma.Language.Path,
  )
where

import Data.HashMap.Strict qualified as HashMap
import GHC.Base (Type)
import Juvix.Compiler.Core.Language.Base (Symbol)
import Juvix.Compiler.Nockma.AnomaLib.Base
import Juvix.Compiler.Nockma.Language.Path
import Juvix.Data.CodeAnn
import Juvix.Prelude hiding (Atom, Path)

data ReplStatement a
  = ReplStatementExpression (ReplExpression a)
  | ReplStatementAssignment (Assignment a)

data ReplExpression a
  = ReplExpressionTerm (ReplTerm a)
  | ReplExpressionWithStack (WithStack a)

data WithStack a = WithStack
  { _withStackStack :: ReplTerm a,
    _withStackTerm :: ReplTerm a
  }

data ReplTerm a
  = ReplName Text
  | ReplTerm (Term a)

newtype Program a = Program
  { _programStatements :: [Statement a]
  }

data Statement a
  = StatementAssignment (Assignment a)
  | StatementStandalone (Term a)

data Assignment a = Assignment
  { _assignmentName :: Text,
    _assignmentBody :: Term a
  }

data Term a
  = TermAtom (Atom a)
  | TermCell (Cell a)
  deriving stock (Show, Eq, Lift, Generic)

instance (Hashable a) => Hashable (Term a)

instance (NFData a) => NFData (Term a)

instance (Serialize a) => Serialize (Term a)

data AnomaLibCall a = AnomaLibCall
  { _anomaLibCallRef :: AnomaLib,
    _anomaLibCallArgs :: Term a
  }
  deriving stock (Show, Eq, Lift, Generic)

instance (Hashable a) => Hashable (AnomaLibCall a)

instance (NFData a) => NFData (AnomaLibCall a)

instance (Serialize a) => Serialize (AnomaLibCall a)

newtype Tag = Tag
  { _unTag :: Text
  }
  deriving stock (Show, Eq, Lift, Generic)

instance Hashable Tag

instance NFData Tag

instance Serialize Tag

data CellInfo a = CellInfo
  { _cellInfoLoc :: Irrelevant (Maybe Interval),
    _cellInfoTag :: Maybe Tag,
    _cellInfoCall :: Maybe (AnomaLibCall a),
    _cellInfoHash :: Int
  }
  deriving stock (Show, Eq, Lift, Generic)

instance (NFData a) => NFData (CellInfo a)

instance (Serialize a) => Serialize (CellInfo a)

data Cell a = Cell'
  { _cellLeft :: Term a,
    _cellRight :: Term a,
    _cellInfo :: CellInfo a
  }
  deriving stock (Show, Lift, Generic)

instance (Eq a) => Eq (Cell a) where
  Cell' l r _ == Cell' l' r' _ = l == l' && r == r'

instance (Hashable a) => Hashable (Cell a) where
  hashWithSalt salt (Cell' _ _ CellInfo {..}) = hashWithSalt salt _cellInfoHash
  hash (Cell' _ _ CellInfo {..}) = _cellInfoHash

instance (NFData a) => NFData (Cell a)

instance (Serialize a) => Serialize (Cell a)

data AtomInfo = AtomInfo
  { _atomInfoHint :: Maybe AtomHint,
    _atomInfoTag :: Maybe Tag,
    _atomInfoLoc :: Irrelevant (Maybe Interval)
  }
  deriving stock (Show, Eq, Lift, Generic)

instance Hashable AtomInfo

instance NFData AtomInfo

instance Serialize AtomInfo

data Atom a = Atom
  { _atom :: a,
    _atomInfo :: AtomInfo
  }
  deriving stock (Show, Lift, Generic)

instance (Eq a) => Eq (Atom a) where
  Atom a _ == Atom b _ = a == b

instance (Hashable a) => Hashable (Atom a) where
  hashWithSalt salt (Atom a _) = hashWithSalt salt a

instance (NFData a) => NFData (Atom a)

instance (Serialize a) => Serialize (Atom a)

data AtomHint
  = AtomHintOp
  | AtomHintPath
  | AtomHintBool
  | AtomHintNil
  | AtomHintVoid
  | AtomHintFunctionsPlaceholder
  | AtomHintStdlibPlaceholder
  | AtomHintString
  deriving stock (Show, Eq, Lift, Generic)

instance Hashable AtomHint

instance NFData AtomHint

instance Serialize AtomHint

data NockOp
  = OpAddress
  | OpQuote
  | OpApply
  | OpIsCell
  | OpInc
  | OpEq
  | OpIf
  | OpSequence
  | OpPush
  | OpCall
  | OpReplace
  | OpHint
  | OpScry
  deriving stock (Show, Bounded, Enum, Eq, Generic, Lift)

instance Hashable NockOp

instance NFData NockOp

instance Serialize NockOp

instance Pretty NockOp where
  pretty = \case
    OpAddress -> "@"
    OpQuote -> "quote"
    OpApply -> "apply"
    OpIsCell -> "isCell"
    OpInc -> "suc"
    OpEq -> "="
    OpIf -> "if"
    OpSequence -> "seq"
    OpPush -> "push"
    OpCall -> "call"
    OpReplace -> "replace"
    OpHint -> "hint"
    OpScry -> "scry"

instance HasNameKind NockOp where
  getNameKind = const KNameFunction
  getNameKindPretty = const KNameFunction

instance PrettyCodeAnn NockOp where
  ppCodeAnn o = annotate (AnnKind (getNameKind o)) . pretty $ o

data NockHint = NockHintPuts
  deriving stock (Show, Eq, Enum, Bounded)

textToStdlibFunctionMap :: HashMap Text StdlibFunction
textToStdlibFunctionMap =
  hashMap
    [ (prettyText f, f) | f <- allElements
    ]

parseStdlibFunction :: Text -> Maybe StdlibFunction
parseStdlibFunction t = textToStdlibFunctionMap ^. at t

textToRmFunctionMap :: HashMap Text RmFunction
textToRmFunctionMap =
  hashMap
    [ (prettyText f, f) | f <- allElements
    ]

parseRmFunction :: Text -> Maybe RmFunction
parseRmFunction t = textToRmFunctionMap ^. at t

textToRmValueMap :: HashMap Text RmValue
textToRmValueMap =
  hashMap
    [ (prettyText f, f) | f <- allElements
    ]

parseRmValue :: Text -> Maybe RmValue
parseRmValue t = textToRmValueMap ^. at t

parseAnomaLib :: Text -> Maybe AnomaLib
parseAnomaLib t =
  AnomaLibFunction . AnomaStdlibFunction <$> parseStdlibFunction t
    <|> AnomaLibFunction . AnomaRmFunction <$> parseRmFunction t
    <|> AnomaLibValue . AnomaRmValue <$> parseRmValue t

atomOps :: HashMap Text NockOp
atomOps = HashMap.fromList [(prettyText op, op) | op <- allElements]

data AnomaLibCallCell a = AnomaLibCallCell
  { _anomaLibCallCell :: AnomaLibCall a,
    _anomaLibCallRaw :: OperatorCell a
  }

data OperatorCell a = OperatorCell
  { _operatorCellOp :: NockOp,
    _operatorCellTag :: Maybe Tag,
    _operatorCellTerm :: Term a
  }

data AutoConsCell a = AutoConsCell
  { _autoConsCellLeft :: Cell a,
    _autoConsCellRight :: Term a
  }

data ParsedCell a
  = ParsedOperatorCell (OperatorCell a)
  | ParsedAutoConsCell (AutoConsCell a)
  | ParsedAnomaLibCallCell (AnomaLibCallCell a)

-- | appends n R
encodedPathAppendRightN :: Natural -> EncodedPath -> EncodedPath
encodedPathAppendRightN n (EncodedPath p) = EncodedPath (f p)
  where
    -- equivalent to applying 2 * x + 1, n times
    f :: Natural -> Natural
    f x = (2 ^ n) * (x + 1) - 1

makeLenses ''Cell
makeLenses ''Tag
makeLenses ''AnomaLibCallCell
makeLenses ''AnomaLibCall
makeLenses ''Atom
makeLenses ''OperatorCell
makeLenses ''AutoConsCell
makeLenses ''Program
makeLenses ''Assignment
makeLenses ''WithStack
makeLenses ''AtomInfo
makeLenses ''CellInfo

mkCell :: (Hashable a) => Term a -> Term a -> Cell a
mkCell l r =
  Cell'
    { _cellLeft = l,
      _cellRight = r,
      _cellInfo = emptyCellInfo {_cellInfoHash = hash (l, r)}
    }

isCell :: Term a -> Bool
isCell = \case
  TermCell {} -> True
  _ -> False

isAtom :: Term a -> Bool
isAtom = not . isCell

atomHint :: Lens' (Atom a) (Maybe AtomHint)
atomHint = atomInfo . atomInfoHint

singletonProgram :: Term a -> Program a
singletonProgram t = Program [StatementStandalone t]

-- | Removes all extra information recursively
removeInfoRec :: forall a. (Hashable a) => Term a -> Term a
removeInfoRec = go
  where
    go :: Term a -> Term a
    go = \case
      TermAtom a -> TermAtom (goAtom a)
      TermCell a -> TermCell (goCell a)

    goAtom :: Atom a -> Atom a
    goAtom (Atom _atom _) =
      Atom
        { _atomInfo = emptyAtomInfo,
          _atom
        }

    goCell :: Cell a -> Cell a
    goCell (Cell l r) = Cell (go l) (go r)

termLoc :: Lens' (Term a) (Maybe Interval)
termLoc f = \case
  TermAtom a -> TermAtom <$> atomLoc f a
  TermCell a -> TermCell <$> cellLoc f a

cellLoc :: Lens' (Cell a) (Maybe Interval)
cellLoc = cellInfo . cellInfoLoc . unIrrelevant

cellTag :: Lens' (Cell a) (Maybe Tag)
cellTag = cellInfo . cellInfoTag

cellCall :: Lens' (Cell a) (Maybe (AnomaLibCall a))
cellCall = cellInfo . cellInfoCall

atomTag :: Lens' (Atom a) (Maybe Tag)
atomTag = atomInfo . atomInfoTag

atomLoc :: Lens' (Atom a) (Maybe Interval)
atomLoc = atomInfo . atomInfoLoc . unIrrelevant

naturalNockOps :: HashMap Natural NockOp
naturalNockOps = HashMap.fromList [(serializeOp op, op) | op <- allElements]

nockOpsNatural :: HashMap NockOp Natural
nockOpsNatural = HashMap.fromList (swap <$> HashMap.toList naturalNockOps)

parseOp :: (Member Fail r) => Natural -> Sem r NockOp
parseOp n = failMaybe (naturalNockOps ^. at n)

serializeOp :: NockOp -> Natural
serializeOp = \case
  OpAddress -> 0
  OpQuote -> 1
  OpApply -> 2
  OpIsCell -> 3
  OpInc -> 4
  OpEq -> 5
  OpIf -> 6
  OpSequence -> 7
  OpPush -> 8
  OpCall -> 9
  OpReplace -> 10
  OpHint -> 11
  OpScry -> 12

class (NockmaEq a) => NockNatural a where
  type ErrNockNatural a :: Type
  nockNatural :: (Member (Error (ErrNockNatural a)) r) => Atom a -> Sem r Natural
  fromNatural :: (Member (Error (ErrNockNatural a)) r) => Natural -> Sem r a
  serializeNockOp :: NockOp -> a
  serializePath :: Path -> a

  errInvalidOp :: Atom a -> ErrNockNatural a

  errInvalidPath :: Atom a -> ErrNockNatural a
  errGetAtom :: ErrNockNatural a -> Atom a

  nockOp :: (Member (Error (ErrNockNatural a)) r) => Atom a -> Sem r NockOp
  nockOp atm = do
    case atm ^. atomHint of
      Just h
        | h /= AtomHintOp -> throw (errInvalidOp atm)
      _ -> return ()
    n <- nockNatural atm
    failWithError (errInvalidOp atm) (parseOp n)

  nockPath :: (Member (Error (ErrNockNatural a)) r) => Atom a -> Sem r Path
  nockPath atm = do
    n <- nockNatural atm
    failWithError (errInvalidPath atm) (decodePath (EncodedPath n))

  nockTrue :: Atom a
  nockFalse :: Atom a
  nockSucc :: Atom a -> Atom a
  nockNil :: Atom a
  nockVoid :: Atom a

nockBool :: (NockNatural a) => Bool -> Atom a
nockBool = \case
  True -> nockTrue
  False -> nockFalse

nockNilTagged :: Text -> Term Natural
nockNilTagged txt = TermAtom (set atomTag (Just (Tag txt)) nockNil)

data NockNaturalNaturalError
  = NaturalInvalidPath (Atom Natural)
  | NaturalInvalidOp (Atom Natural)
  deriving stock (Show)

nockTrueLiteral :: Term Natural
nockTrueLiteral = OpQuote # TermAtom (nockTrue @Natural)

nockFalseLiteral :: Term Natural
nockFalseLiteral = OpQuote # TermAtom (nockFalse @Natural)

nockBoolLiteral :: Bool -> Term Natural
nockBoolLiteral b
  | b = nockTrueLiteral
  | otherwise = nockFalseLiteral

nockHintName :: NockHint -> Text
nockHintName = \case
  NockHintPuts -> "puts"

nockHintValue :: NockHint -> Natural
nockHintValue = \case
  NockHintPuts -> 0x73747570

nockHintAtom :: NockHint -> Term Natural
nockHintAtom hint =
  TermAtom
    Atom
      { _atomInfo = emptyAtomInfo,
        _atom = nockHintValue hint
      }

instance NockNatural Natural where
  type ErrNockNatural Natural = NockNaturalNaturalError
  nockNatural a = return (a ^. atom)
  fromNatural = return
  nockTrue = Atom 0 (atomHintInfo AtomHintBool)
  nockFalse = Atom 1 (atomHintInfo AtomHintBool)
  nockNil = Atom 0 (atomHintInfo AtomHintNil)
  errGetAtom = \case
    NaturalInvalidPath a -> a
    NaturalInvalidOp a -> a
  nockSucc = over atom succ
  nockVoid = Atom 0 (atomHintInfo AtomHintVoid)
  errInvalidOp atm = NaturalInvalidOp atm
  errInvalidPath atm = NaturalInvalidPath atm
  serializeNockOp = serializeOp
  serializePath = (^. encodedPath) . encodePath

atomHintInfo :: AtomHint -> AtomInfo
atomHintInfo h =
  emptyAtomInfo
    { _atomInfoHint = Just h
    }

setAtomHint :: AtomHint -> Atom a -> Atom a
setAtomHint h = set (atomInfo . atomInfoHint) (Just h)

class IsNock nock where
  toNock :: nock -> Term Natural

instance IsNock (Term Natural) where
  toNock = id

instance IsNock (Atom Natural) where
  toNock = TermAtom

instance IsNock (Cell Natural) where
  toNock = TermCell

instance IsNock Natural where
  toNock = TAtom

instance IsNock NockOp where
  toNock op = toNock (Atom (serializeOp op) (atomHintInfo AtomHintOp))

instance IsNock Bool where
  toNock = \case
    False -> toNock (nockFalse @Natural)
    True -> toNock (nockTrue @Natural)

instance IsNock Path where
  toNock pos = TermAtom (Atom (encodePath pos ^. encodedPath) (atomHintInfo AtomHintPath))

instance IsNock EncodedPath where
  toNock = toNock . decodePath'

class HasTag a where
  atTag :: Lens' a (Maybe Tag)

instance (HasTag (Term a)) where
  atTag = lens getTag setTag
    where
      getTag :: Term x -> Maybe Tag
      getTag = \case
        TermAtom x -> x ^. atomTag
        TermCell x -> x ^. cellTag

      setTag :: Term a -> Maybe Tag -> Term a
      setTag t newTag = case t of
        TermAtom x -> TermAtom (set atomTag newTag x)
        TermCell x -> TermCell (set cellTag newTag x)

instance (HasTag (Cell a)) where
  atTag = cellTag

instance (HasTag (Atom a)) where
  atTag = atomTag

infixr 1 @.

(@.) :: Text -> Cell Natural -> Cell Natural
tag @. c = set cellTag (Just (Tag tag)) c

infixr 1 @

(@) :: (HasTag a) => Text -> a -> a
tagTxt @ c = set atTag (Just (Tag tagTxt)) c

infixr 5 #.

(#.) :: (IsNock x, IsNock y) => x -> y -> Cell Natural
a #. b = Cell (toNock a) (toNock b)

infixr 5 #

(#) :: (IsNock x, IsNock y) => x -> y -> Term Natural
a # b = TermCell (a #. b)

infixl 1 >>#.

(>>#.) :: (IsNock x, IsNock y) => x -> y -> Cell Natural
a >>#. b = OpSequence #. a # b

infixl 1 >>#

(>>#) :: (IsNock x, IsNock y) => x -> y -> Term Natural
a >># b = TermCell (a >>#. b)

opCall :: Text -> Path -> Term Natural -> Term Natural
opCall txt p t = TermCell (txt @ (OpCall #. (p # t)))

opReplace :: Text -> Path -> Term Natural -> Term Natural -> Term Natural
opReplace txt p t1 t2 = TermCell (txt @ OpReplace #. ((p #. t1) #. t2))

opAddress :: Text -> Path -> Term Natural
opAddress txt p = TermCell (txt @ OpAddress #. p)

opQuote :: (IsNock x) => Text -> x -> Term Natural
opQuote txt p = TermCell (txt @ OpQuote #. p)

opTrace :: Term Natural -> Term Natural
opTrace val = OpHint # (nockHintAtom NockHintPuts # val) # val

opTrace' :: Term Natural -> Term Natural -> Term Natural
opTrace' msg val = OpHint # (nockNilTagged "opTrace'" # msg) # val

{-# COMPLETE Cell #-}

pattern Cell :: (Hashable a) => Term a -> Term a -> Cell a
pattern Cell {_cellLeft', _cellRight'} <- Cell' _cellLeft' _cellRight' _
  where
    Cell a b = mkCell a b

{-# COMPLETE TCell, TAtom #-}

pattern TCell :: (Hashable a) => Term a -> Term a -> Term a
pattern TCell l r <- TermCell (Cell' l r _)
  where
    TCell a b = TermCell (mkCell a b)

pattern TAtom :: a -> Term a
pattern TAtom a <- TermAtom (Atom a _)
  where
    TAtom a = TermAtom (Atom a emptyAtomInfo)

emptyCellInfo :: CellInfo a
emptyCellInfo =
  CellInfo
    { _cellInfoCall = Nothing,
      _cellInfoTag = Nothing,
      _cellInfoLoc = Irrelevant Nothing,
      _cellInfoHash = 0
    }

emptyAtomInfo :: AtomInfo
emptyAtomInfo =
  AtomInfo
    { _atomInfoHint = Nothing,
      _atomInfoTag = Nothing,
      _atomInfoLoc = Irrelevant Nothing
    }

class NockmaEq a where
  nockmaEq :: a -> a -> Bool

instance NockmaEq Natural where
  nockmaEq a b = a == b

instance (NockmaEq a) => NockmaEq [a] where
  nockmaEq a b =
    case zipExactMay a b of
      Nothing -> False
      Just z -> all (uncurry nockmaEq) z

instance (NockmaEq a) => NockmaEq (Atom a) where
  nockmaEq = nockmaEq `on` (^. atom)

instance (Hashable a, NockmaEq a) => NockmaEq (Term a) where
  nockmaEq = \cases
    (TermAtom a) (TermAtom b) -> nockmaEq a b
    (TermCell a) (TermCell b) -> nockmaEq a b
    TermCell {} TermAtom {} -> False
    TermAtom {} TermCell {} -> False

instance (Hashable a, NockmaEq a) => NockmaEq (Cell a) where
  nockmaEq (Cell l r) (Cell l' r') = nockmaEq l l' && nockmaEq r r'

crash :: Term Natural
crash = ("crash" @ OpAddress # OpAddress # OpAddress)

unfoldList :: Term Natural -> [Term Natural]
unfoldList = ensureNockmList . nonEmpty . unfoldTuple
  where
    ensureNockmList :: Maybe (NonEmpty (Term Natural)) -> [Term Natural]
    ensureNockmList = \case
      Nothing -> err
      Just l -> case l ^. _unsnoc1 of
        (ini, lst)
          | nockmaEq lst (nockNilTagged "unfoldList") -> ini
          | otherwise -> err
      where
        err :: x
        err = error "Nockma lists must have the form [x1 .. xn 0]"

unfoldTuple :: Term Natural -> [Term Natural]
unfoldTuple = toList . unfoldTuple1

unfoldTuple1 :: Term Natural -> NonEmpty (Term Natural)
unfoldTuple1 = nonEmpty' . run . execOutputList . go
  where
    go :: (Members '[Output (Term Natural)] r) => Term Natural -> Sem r ()
    go t =
      case t of
        TermAtom {} -> output t
        TermCell (Cell l r) -> output l >> go r

foldTerms :: NonEmpty (Term Natural) -> Term Natural
foldTerms = foldr1 (#)

-- | The elements will not be evaluated.
makeList :: (Foldable f) => f (Term Natural) -> Term Natural
makeList ts = foldTerms (toList ts `prependList` pure (nockNilTagged "makeList"))

-- | The elements of the list will be evaluated to create the list.
remakeList :: (Foldable l) => l (Term Natural) -> Term Natural
remakeList ts = foldTerms (toList ts `prependList` pure (OpQuote # nockNilTagged "remakeList"))

mkEmptyAtom :: a -> Atom a
mkEmptyAtom x =
  Atom
    { _atomInfo = emptyAtomInfo,
      _atom = x
    }
