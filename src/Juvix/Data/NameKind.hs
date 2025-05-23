module Juvix.Data.NameKind where

import Juvix.Extra.Serialize
import Juvix.Prelude.Base
import Juvix.Prelude.Pretty
import Prettyprinter.Render.Terminal

data NameKind
  = -- | Constructor name.
    KNameConstructor
  | -- | Name introduced by the inductive keyword.
    KNameInductive
  | -- | Name of a defined function (top level or let/where block).
    KNameFunction
  | -- | A locally bound name (patterns, arguments, etc.).
    KNameLocal
  | -- | An axiom.
    KNameAxiom
  | -- | A local module name.
    KNameLocalModule
  | -- | A top module name.
    KNameTopModule
  | -- | A fixity name.
    KNameFixity
  | -- | An alias name. Only used in the declaration site.
    KNameAlias
  deriving stock (Show, Eq, Data, Generic)

$(genSingletons [''NameKind])

instance Serialize NameKind

instance NFData NameKind

class HasNameKind a where
  getNameKind :: a -> NameKind

  getNameKindPretty :: a -> NameKind

class HasNameKindAnn a where
  annNameKind :: NameKind -> a

instance HasNameKind NameKind where
  getNameKind = id
  getNameKindPretty = id

instance Pretty NameKind where
  pretty = pretty . nameKindText

nameKindWithArticle :: NameKind -> Text
nameKindWithArticle = withArticle . nameKindText

nameKindText :: NameKind -> Text
nameKindText = \case
  KNameConstructor -> "constructor"
  KNameInductive -> "inductive type"
  KNameFunction -> "function"
  KNameLocal -> "variable"
  KNameAxiom -> "axiom"
  KNameLocalModule -> "local module"
  KNameTopModule -> "module"
  KNameFixity -> "fixity"
  KNameAlias -> "alias"

isExprKind :: (HasNameKind a) => a -> Bool
isExprKind k = case getNameKind k of
  KNameLocalModule -> False
  KNameTopModule -> False
  _ -> True

isModuleKind :: (HasNameKind a) => a -> Bool
isModuleKind k = case getNameKind k of
  KNameLocalModule -> True
  KNameTopModule -> True
  _ -> False

canBeCompiled :: (HasNameKind a) => a -> Bool
canBeCompiled k = case getNameKind k of
  KNameConstructor -> True
  KNameInductive -> True
  KNameFunction -> True
  KNameAxiom -> True
  KNameLocal -> False
  KNameLocalModule -> False
  KNameTopModule -> False
  KNameFixity -> False
  KNameAlias -> False

nameKindAnsi :: NameKind -> AnsiStyle
nameKindAnsi k = case k of
  KNameConstructor -> colorDull Blue
  KNameInductive -> colorDull Green
  KNameAxiom -> colorDull Magenta
  KNameLocalModule -> color Cyan
  KNameFunction -> colorDull Yellow
  KNameLocal -> mempty
  KNameAlias -> mempty
  KNameTopModule -> color Cyan
  KNameFixity -> mempty
