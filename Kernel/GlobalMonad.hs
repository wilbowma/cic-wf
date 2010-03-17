{-# LANGUAGE PackageImports, FlexibleContexts, FlexibleInstances,
  DeriveDataTypeable #-}
module Kernel.GlobalMonad where

import "mtl" Control.Monad.Reader
import Control.Exception

import Data.Typeable

import qualified Syntax.Abstract as A
import Syntax.Global
import Syntax.Name
import Syntax.Internal
import qualified Syntax.Scope as S

import Kernel.TCM
import qualified Kernel.TypeChecking as T
import qualified Kernel.Whnf as W

import Utils.Misc

class (Functor gm,
       MonadIO gm,
       LookupName Global gm,
       ExtendName Global gm) => TCGlobalMonad gm where

data CommandError = AlreadyDefined Name
                    deriving(Typeable, Show)

instance Exception CommandError

alreadyDefined :: (TCGlobalMonad gm) => Name -> gm ()
alreadyDefined = liftIO . throwIO . AlreadyDefined

instance (TCGlobalMonad gm) => MonadTCM (ReaderT TCEnv gm) where

instance (TCGlobalMonad gm) => S.ScopeMonad (ReaderT [Name] gm) where

infer :: (TCGlobalMonad gm) => A.Expr -> gm (Term, Type)
infer = flip runReaderT [] . T.infer

check :: (TCGlobalMonad gm) => A.Expr -> Term -> gm Term
check e = flip runReaderT []  . T.check e

isSort :: (TCGlobalMonad gm) => Term -> gm Sort
isSort = flip runReaderT [] . T.isSort

scope :: (S.Scope a, TCGlobalMonad gm) => a -> gm a
scope = flip runReaderT [] . S.scope

scopeSub :: (S.Scope a, TCGlobalMonad gm) => [Name] -> a -> gm a
scopeSub xs = flip runReaderT xs . S.scope

normalForm :: (W.NormalForm a, TCGlobalMonad gm) => a -> gm a
normalForm = flip runReaderT [] . W.normalForm

addGlobal :: (TCGlobalMonad gm) => Name -> Global -> gm ()
addGlobal x g = do mWhen (definedName x) $ alreadyDefined x
                   extendName x g

checkIfDefined :: (TCGlobalMonad gm) => [Name] -> gm ()
checkIfDefined [] = return ()
checkIfDefined (x:xs) = do mWhen (definedName x) $ alreadyDefined x
                           checkIfDefined xs