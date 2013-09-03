{-# LANGUAGE FunctionalDependencies, MultiParamTypeClasses,
    TypeSynonymInstances, FlexibleInstances, FlexibleContexts,
    UndecidableInstances
  #-}

module TypeChecking.TypeChecking where

import qualified Syntax.Abstract as A
import Syntax.Common
import Syntax.Position
import Syntax.Internal

import TypeChecking.TCM

maxSort :: (MonadTCM tcm) => Sort -> Sort -> tcm Sort

inferBinds :: (MonadTCM tcm) => A.Context -> tcm (Context, Sort)

infer :: (MonadTCM tcm) => A.Expr -> tcm (Term, Type)

check :: (MonadTCM tcm) => A.Expr -> Type -> tcm Term

checkList :: (MonadTCM tcm) => [A.Expr] -> Context -> tcm [Term]

isSort :: (MonadTCM tcm) => Range -> Term -> tcm Sort