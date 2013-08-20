{- cicminus
 - Copyright 2011 by Jorge Luis Sacchini
 -
 - This file is part of cicminus.
 -
 - cicminus is free software: you can redistribute it and/or modify it under the
 - terms of the GNU General Public License as published by the Free Software
 - Foundation, either version 3 of the License, or (at your option) any later
 - version.

 - cicminus is distributed in the hope that it will be useful, but WITHOUT ANY
 - WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 - FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 - details.
 -
 - You should have received a copy of the GNU General Public License along with
 - cicminus. If not, see <http://www.gnu.org/licenses/>.
 -}

{-# LANGUAGE FlexibleInstances, StandaloneDeriving
  #-}

-- | Abstract syntax returned by the parser.
--
--   We reuse the datatype 'Expr' and related for later phases (in particular,
--   for scope checking). Constructors 'Bound', 'Constr' are not used by
--   the parser.

module Syntax.Abstract where

import Data.Function
import Data.Maybe
import Data.List (intercalate, sortBy)
import qualified Data.Foldable as Fold

import Text.PrettyPrint.HughesPJ hiding (comma)

import Syntax.Common
import Syntax.Position
import Syntax.Size

import Utils.Pretty

-- | The main data type of expressions
data Expr =
  Ann Range Expr Expr       -- ^ Annotated term with type, e.g. @ M :: T @
  | Sort Range Sort
  | Pi Range Context Expr    -- ^ Dependent product type.
                            --   e.g. @ forall (x1 ... xn : A), B @
  | Arrow Range (Implicit Expr) Expr
  | Ident Range Name        -- ^ Identifiers
--  | EVar Range (Maybe Int)  -- ^ existential variable
  | Lam Range Context Expr   -- ^ Abstractions, e.g. @ fun (x1 ... xn : A) => B @
  | App Range Expr Expr     -- ^ Applications
--  | Let Range LetBind Expr
  | Case CaseExpr           -- ^ Case expressions
  | Fix FixExpr             -- ^ Fixpoints
  | Meta Range (Maybe Int)  -- ^ Unspecified terms

  -- The following constructors are filled by the scope checker, but do not
  -- appear in a correctly parsed expression
  | Bound Range Name Int     -- ^ Bound variables. The name argument is used by
                             -- the pretty printer.
  | Constr Range Name (Name, Int) [Expr] [Expr]
                             -- ^ Constructors are fully applied. Arguments are
                             --
                             -- * Name of the constructor
                             --
                             -- * Name of the inductive type and id of the
                             --   constructor
                             --
                             -- * Parameters (of the inductive type)
                             --
                             -- * Actual arguments of the constructor
  | Ind Range Annot Name [Expr] -- Inductive types are applied to parameters
  -- Natural numbers are predefined
  | Number Range Int


mkApp :: Expr -> [Expr] -> Expr
mkApp = foldl (\x y -> App (fuseRange x y) x y)


unApp :: Expr -> (Expr, [Expr])
unApp (App _ e1 e2) = (func, args ++ [e2])
  where (func, args) = unApp e1
unApp e             = (e, [])

mkArrow :: Expr -> Expr -> Expr
mkArrow e1 e2 = Pi noRange (ctxSingle (Bind noRange [noName]
                                       (mkImplicit False (Just e1)))) e2

unPi :: Expr -> (Context, Expr)
unPi (Pi _ ctx e) = (ctx +: ctx', e')
  where
    (ctx', e') = unPi e
unPi (Arrow _ e1 e2) = (ctx', e2')
  where
    (ctx, e2') = unPi e2
    ctx' = mkBind (range e1) noName (isImplicit e1) (implicitValue e1) <| ctx
unPi e = (ctxEmpty, e)

-- class HasExpr a where
--   expr :: a -> Maybe Expr

-- instance HasExpr Expr where
--   expr = Just

-- instance HasExpr (Maybe Expr) where
--   expr = id

-- instance HasExpr a => HasExpr (Named a) where
--   expr = expr . namedValue

-- instance HasExpr a => HasExpr (Implicit a) where
--   expr = expr . implicitValue

-- instance HasExpr a => HasExpr (Ranged a) where
--   expr = expr . rangedValue

data LetBind = LetBind Range Name (Maybe Expr) Expr
               deriving(Show)


-- | Universes
data Sort
    = Type (Maybe Int)
    | Prop
    deriving(Eq)


mkProp, mkType :: Range -> Expr
mkProp r = Sort r Prop
mkType r = Sort r (Type Nothing)

instance Show Sort where
  show Prop = "Prop"
  show (Type (Just n)) = "Type<" ++ show n ++ ">"
  show (Type Nothing)  = "Type"

instance Pretty Sort where
  prettyPrint Prop = text "Prop"
  prettyPrint (Type (Just n)) = text "Type" <> prettyPrintIndex n
  prettyPrint (Type Nothing)  = text "Type"

prettyPrintIndex :: Int -> Doc
prettyPrintIndex = text . map num2Sub . show
  where
    num2Sub c = fromJust (lookup c subTable) -- 'E' should never occur
    subTable = zip ['0'..'9'] ['\x2080'..'\x2089']


-- | Binds and context
data Bind = Bind Range [Name] (Implicit (Maybe Expr))
            deriving (Eq)
                     -- ^ e.g. @(x y : A)@. Name list must be non-empty.
                     -- Nothing name means "_" (See parsing of identifiers)

instance Show Bind where
  show (Bind _ xs t) = concat [ show xs
                              , " : "
                              , show t]


instance HasNames Bind where
  name (Bind _ x _) = name x

instance HasRange Bind where
  range (Bind r _ _) = r

instance SetRange Bind where
  setRange r (Bind _ x y) = Bind r x y

instance HasImplicit Bind where
  isImplicit (Bind _ _ x) = isImplicit x
  modifyImplicit f (Bind r xs i) = Bind r xs (modifyImplicit f i)

-- instance HasExpr Bind where
--   expr (Bind _ _ x) = expr x

type Context = Ctx Bind


-- | Case expressions

data CaseExpr = CaseExpr {
  caseRange    :: Range,
  caseArg      :: Expr,         -- ^ Argument of the case
  caseAsName   :: Maybe Name,   -- ^ Bind for the argument in the return type
  caseInName   :: Maybe CaseIn, -- ^ Specification of the subfamily of the
                                -- inductive type of the argument
  caseWhere    :: Maybe Subst,  -- ^ Substitution that unifies the indices of
                                -- the argument and the subfamily given in the
                                -- specification
  caseReturn   :: Maybe Expr,   -- ^ Return type
  caseBranches :: [Branch]
  } deriving(Show)


data CaseIn = CaseIn {
  inRange :: Range,
  inBind  :: Context,     -- ^ Variables free in the indices of the subfamily
  inInd   :: Name,        -- ^ The inductive type of the case
  inArgs  :: [Expr]       -- ^ The specification of the subfamily
  } deriving(Show)


data Branch = Branch {
  brRange     :: Range,
  brName      :: Name,
  brConstrId  :: Int,
  brArgsNames :: [Name],
  brBody      :: Expr,
  brSubst     :: Maybe Subst
  } deriving(Show)


newtype Subst = Subst { unSubst :: [Assign] }
                deriving(Show)

sortSubst :: Subst -> Subst
sortSubst (Subst sg) = Subst $ sortBy (compare `on` assgnBound) sg


data Assign = Assign {
  assgnRange :: Range,
  assgnName :: Name,
  assgnBound :: Int,
  assgnExpr :: Expr
  } deriving(Show)


-- | (Co-)fix expressions
data FixExpr = FixExpr { fixRange :: Range
                       , fixKind  :: InductiveKind
                       , fixNum   :: Int -- only used for fixpoints (not cofixpoints)
                       , fixName  :: Name
                       , fixType  :: Expr
                       , fixBody  :: Expr
                       } deriving(Show)


-- | Global declarations
data Declaration =
  Definition Range Name (Maybe Expr) Expr
  | Assumption Range Name Expr
  | Inductive Range InductiveDef
  | Eval Expr
  | Check Expr (Maybe Expr)
  deriving(Show)


-- | (Co-)inductive definitions
data InductiveDef = InductiveDef
                    { indName   :: Name
                    , indKind   :: InductiveKind
                    , indPars   :: Context
                    , indPolarities :: [Polarity]
                    , indType   :: Expr
                    , indConstr :: [Constructor]
                    }


-- | Contructors
data Constructor = Constructor
                   { constrRange :: Range
                   , constrName  :: Name
                   , constrType  :: Expr
                   }


-- | Equality on expressions is used by the reifier ("InternaltoAbstract")
--   to join consecutive binds with the same type.

deriving instance Eq Expr
deriving instance Eq FixExpr
deriving instance Eq CaseExpr
deriving instance Eq Branch
deriving instance Eq Subst
deriving instance Eq CaseIn
deriving instance Eq Assign

-- instance Eq Expr where
--   (Sort _ s1) == (Sort _ s2) = s1 == s2
--   (Pi _ ctx1 t1) == (Pi _ ctx2 t2) = ctx1 == ctx2 &&
--                                      t1 == t2
--   (Bound _ x1 n1) == (Bound _ x2 n2) = x1 == x2 && n1 == n2
--   (Ident _ x1) == (Ident _ x2) = x1 == x2
--   (Lam _ ctx1 t1) == (Lam _ ctx2 t2) = ctx1 == ctx2 &&
--                                        t1 == t2
--   (App _ e1 e2) == (App _ e3 e4) = e1 == e3 && e2 == e4
--   (Ind _ a1 i1 ps1) == (Ind _ a2 i2 ps2) = a1 == a2 && i1 == i2 && ps1 == ps2
--   _ == _ = False


mkBind :: Range -> Name -> Bool -> Expr -> Bind
mkBind r x i e = Bind r [x] (mkImplicit i (Just e))












-- TODO: print implicit
-- instance Show Bind where
--   show b = around $ concat [show (name b), " : ", show (expr b)]
--     where
--       around x | isImplicit b = "{" ++ x ++ "}"
--                | otherwise    = "(" ++ x ++ ")"

-- instance Eq Bind where
--   (==) b1 b2 = isImplicit b1 == isImplicit b2
--                && name b1 == name b2 && expr b1 == expr b2


-- | Instances of the class HasNames. This class is used for things that behave
--   like binds

-- instance HasNames Bind where
--   name = name . bindNames

instance HasNames CaseIn where
  name = name . inBind


instance HasRange Expr where
  range (Ann r _ _) = r
  range (Sort r _) = r
  range (Pi r _ _) = r
  range (Arrow r _ _) = r
  range (Ident r _) = r
  range (Bound r _ _) = r
  range (Meta r _) = r
--  range (EVar r _) = r
  range (Lam r _ _) = r
  range (App r _ _) = r
--  range (Let r _ _) = r
  range (Case c) = range c
  range (Fix f) = range f
  range (Constr r _ _ _ _) = r
  range (Ind r _ _ _) = r
  range (Number r _) = r

instance HasRange CaseExpr where
  range = caseRange

instance HasRange FixExpr where
  range = fixRange

instance SetRange Expr where
  setRange r (Ann _ x y) = Ann r x y
  setRange r (Sort _ x) = Sort r x
  setRange r (Pi _ x y) = Pi r x y
  setRange r (Arrow _ x y) = Arrow r x y
  setRange r (Ident _ x) = Ident r x
  setRange r (Bound _ x y) = Bound r x y
  setRange r (Meta _ x) = Meta r x
--  setRange (EVar r _) = r
  setRange r (Lam _ x y) = Lam r x y
  setRange r (App _ x y) = App r x y
--  setRange (Let r _ _) = r
  setRange r (Case c) = Case $ setRange r c
  setRange r (Fix f) = Fix $ setRange r f
  setRange r (Constr _ x y z w) = Constr r x y z w
  setRange r (Ind _ x y z) = Ind r x y z
  setRange r (Number _ x) = Number r x

instance SetRange CaseExpr where
  setRange r c = c { caseRange = r }

instance SetRange FixExpr where
  setRange r f = f { fixRange = r }

instance HasRange Constructor where
  range (Constructor r _ _) = r

instance HasRange Branch where
  range = brRange

instance HasRange Subst where
  range = range . unSubst

instance HasRange Assign where
  range = assgnRange

-- | Instances of Show and Pretty. For bound variables, the pretty printer uses
--   the name directly.
--
--   Printing a parsed expression should give the same result modulo comments
--   and whitespaces. In particular, there is no effort in removing unused
--   variable names (e.g., changing @ forall x:A, B @ for @ A -> B @ if @ x @ is
--   not free in @ B @.

-- TODO: pretty print binds
-- instance Pretty Bind where
--   prettyPrint b = text (show b)

-- TODO:
--  * check precedences
--  * use proper aligment of constructors and branches

instance Pretty Expr where
  prettyPrintDec = pp
    where
      pp :: Int -> Expr -> Doc
      pp n (Ann _ e1 e2) = parensIf (n > 1) $ hsep [pp 2 e1, doubleColon,
                                                    pp 0 e2]
      pp _ (Sort _ s) = prettyPrint s
      pp n (Pi _ ctx e) = parensIf (n > 0) $ nestedPi ctx e
      pp n (Arrow _ e1 e2) = parensIf (n > 0) $ sep [dom, text "->", pp 0 e2]
        where
          dom | isImplicit e1 = braces $ pp 0 (implicitValue e1)
              | otherwise     = pp 0 (implicitValue e1)
      pp _ (Ident _ x) = prettyPrint x -- text $ "[" ++ x ++ "]"
      pp _ (Bound _ x k) = prettyPrint x <> (text $ "[" ++ show k ++ "]") -- text "<" ++ x ">"
      pp _ (Meta _ Nothing) = text "_"
      pp _ (Meta _ (Just k)) = text "?" <> int k
--      pp _ (EVar _ Nothing) = text "_"
--      pp _ (EVar _ (Just n)) = char '?' <> int n
      pp n (Lam _ bs e) = parensIf (n > 0) $ nestedLam bs e
      pp n (App _ e1 e2) = parensIf (n > 2) $ hsep [pp 2 e1, pp 3 e2]
      pp n (Case c) = parensIf (n > 0) $ prettyPrint c
      pp n (Fix f) = parensIf (n > 0) $ prettyPrint f
      pp _ (Ind _ a x es) = hcat ([prettyPrint x, langle, prettyPrint a, rangle] ++ map prettyPrint es)
      pp n (Constr _ x _ pars args) =
        parensIf (n > 2) $ prettyPrint x <+> hsep (map (pp lvl) (pars ++ args))
          where lvl = if length pars + length args == 0 then 0 else 3
      pp _ (Number _ n) = text $ show n


      nestedPi :: Context -> Expr -> Doc
      nestedPi ctx e = text "Π" <+> fsep (map (prettyBind paren) bs)
                       <> comma <+> prettyPrint e
        where
          bs = bindings ctx
          paren = ctxLen ctx > 1

      nestedLam :: Context -> Expr -> Doc
      nestedLam ctx e =
        hang (text "λ" <+> fsep (map (prettyBind paren) bs) <+> implies)
             2 (prettyPrint e)
        where
          paren = ctxLen ctx > 1
          bs = bindings ctx

prettyBind :: Bool -> Bind -> Doc
prettyBind b (Bind _ xs t) =
  around $ hsep [ hsep (map prettyPrint xs)
                , colon, prettyPrint (fromJust (implicitValue t))]
    where
      around | b || isImplicit t = if isImplicit t then braces else parens
             | otherwise = id

instance Pretty CaseExpr where
  prettyPrint (CaseExpr _ arg asn inn subst ret brs) =
    sep [ maybePPrint ppRet ret
        , sep [ sep [ hsep [ text "case"
                           , maybePPrint ppAs asn
                           , prettyPrint arg ]
                    , maybePPrint ppIn inn <+>  maybePPrint ppSubst subst
                      <+> text "of"
                ]
              , sep (map (nest 2 . (bar <+>) . prettyPrint) brs)
              ]
        ]
      where
        ppRet r   = hsep [langle, prettyPrint r, rangle]
        ppAs a    = hsep [prettyPrint a, defEq]
        ppIn i    = hsep [text "in", prettyPrint i]
        ppSubst s | null (unSubst s) = empty
                  | otherwise        = text "where" <+> prettyPrint s
        maybePPrint :: (Pretty a) => (a -> Doc) -> Maybe a -> Doc
        maybePPrint = maybe empty

instance Pretty CaseIn where
  prettyPrint (CaseIn _ ctx i args) =
    hsep $ context ++ [prettyPrint i] ++ map prettyPrint args
      where
        bs = hsep (map (prettyBind True) (bindings ctx))
        context = [lbrack, bs, rbrack]

instance Pretty Subst where
  prettyPrint = hsep . map (parens . prettyPrint) . unSubst

instance Pretty Assign where
  prettyPrint (Assign _ x _ e) = hsep [prettyPrint x, defEq, prettyPrint e]

instance Pretty Branch where
  prettyPrint (Branch _ x _ args body whSubst) =
    hsep $ prettyPrint x : map prettyPrint args ++ [implies, prettyPrint body]

instance Pretty FixExpr where
  prettyPrint (FixExpr _ k n x tp body) =
    hsep [ppName k, prettyPrint x, colon,
          prettyPrint tp, defEq]
    $$ (nest 2 $ prettyPrint body)
    where ppName I   = text "fix" <> (prettyPrintIndex n)
          ppName CoI = text "cofix"

instance Pretty Declaration where
  prettyPrint (Definition _ x (Just e1) e2) =
    sep [ sep [ hsep [text "define", prettyPrint x]
              , nest 2 $ hsep [colon, prettyPrint e1] ]
        , nest 2 $ hsep [ defEq, prettyPrint e2]
        ]
  prettyPrint (Definition _ x Nothing e2) =
    hsep [text "define", prettyPrint x, defEq] $+$ nest 2 (prettyPrint e2)
  prettyPrint (Assumption _ x e) =
    hsep [text "assume", prettyPrint x, colon, prettyPrint e]
  prettyPrint (Inductive _ indDef) = prettyPrint indDef
  prettyPrint (Eval e) =
    hsep [text "eval", prettyPrint e]
  prettyPrint (Check e1 e2) =
    hsep [text "check", prettyPrint e1, ppMaybe e2]
    where
      ppMaybe (Just e) = colon <+> prettyPrint e
      ppMaybe Nothing = empty

-- instance Pretty (Maybe Expr) where
--   prettyPrint (Just e) = empty <+> colon <+> prettyPrint e
--   prettyPrint Nothing = empty

instance Pretty InductiveDef where
  prettyPrint (InductiveDef x k ps pols e cs) =
    sep $ ind : map (nest 2 . (bar <+>) . prettyPrint) cs
      where ind = hsep [text kind, prettyPrint x,
                        hsep (map (prettyBind True) (bindings ps)), colon,
                        prettyPrint e, defEq]
            kind = case k of
                     I   -> "data"
                     CoI -> "codata"

-- instance Pretty Parameter where
--   prettyPrint (Parameter _ np tp) =
--     parens $ hsep [ ppNames, colon, prettyPrint tp ]
--       where ppNames = hsep $ map (\(n,p) -> prettyPrint n <+> prettyPrint p) np

instance Pretty Constructor where
  prettyPrint c =
    hsep [prettyPrint (constrName c), colon, prettyPrint (constrType c)]

instance Pretty [Declaration] where
  prettyPrint = vcat . map ((<> dot) . prettyPrint)


-- instance Pretty [Bind] where
--   prettyPrint xs = foldr (\x r -> prettyPrint x <> comma <> r) (text "") xs




------------------------
--- The instances below are used only for debugging

instance Show Expr where
  show (Ann _ e1 e2) = concat [show e1, " :: ", show e2]
  show (Sort _ s) = show s
  show (Pi _ ctx e) = concat $ "Pi " : map show (Fold.toList ctx) ++ [", ", show e]
  show (Arrow _ e1 e2) = concat $ [show e1, " -> ", show e2]
  show (Ident _ x) = show x
  show (Lam _ ctx e) = concat $ "fun " : map show (Fold.toList ctx) ++ [" => ", show e]
  show (App _ e1 e2) = concat [show e1, " (", show e2, ")"]
  show (Case c) = show c
  show (Fix f) = show f
  show (Bound _ x n) = concat [show x, "[", show n, "]"]
  show (Meta _ Nothing) = show "_"
  show (Meta _ (Just k)) = '?' : show k
  show (Constr _ x i ps as) = concat $ [show x, show i, "(", intercalate ", " (map show (ps ++ as)), ")"]
  show (Ind _ a x args) = concat $ [show x, "<", show a, ">"] ++ map show args
  show (Number _ n) = show n


instance Show InductiveDef where
  show (InductiveDef name k pars pols tp constr) =
    concat $ ["Inductive ", show name, " ", show pars, " : ", show tp,
              " := "] ++ map show constr

instance Show Constructor where
  show (Constructor _ name tp) =
    concat [" | ", show name, " : ", show tp]

-- instance Show Parameter where
--   show (Parameter _ pol tp) = concatMap showNamePol pol ++ ": " ++ show tp
--     where showNamePol (x, p) = show x ++ show p ++ " "

