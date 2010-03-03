{-# LANGUAGE PackageImports, FlexibleContexts, FlexibleInstances,
  DeriveDataTypeable #-}
module Kernel.Command where

import "mtl" Control.Monad.Trans
import "mtl" Control.Monad.Reader
import Control.Exception

import Data.Foldable hiding (forM_)
import Data.Typeable

import System.IO

import qualified Syntax.Abstract as A
import Syntax.Global
import Syntax.Name
import Syntax.Internal
import Syntax.Parser
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

scope :: (TCGlobalMonad gm) => A.Expr -> gm A.Expr
scope = flip runReaderT [] . S.scope

scopeSub :: (TCGlobalMonad gm) => [Name] -> A.Expr -> gm A.Expr
scopeSub xs = flip runReaderT xs . S.scope

normalForm :: (TCGlobalMonad gm) => Term -> gm Term
normalForm = flip runReaderT [] . W.normalForm


checkCommand :: (TCGlobalMonad gm) => A.Command -> gm ()
checkCommand (A.Definition x t u) = processDef x t u
checkCommand (A.AxiomCommand x t) = processAxiom x t
checkCommand (A.Load xs) = processLoad xs

processLoad :: (TCGlobalMonad gm) => FilePath -> gm ()
processLoad xs = do h <- liftIO $ openFile xs ReadMode
                    ss <- liftIO $ hGetContents h
                    cs <- runParser xs parseFile ss
                    liftIO $ hClose h
                    forM_ cs checkCommand

processAxiom :: (TCGlobalMonad gm) => Name -> A.Expr -> gm ()
processAxiom x t = do t1 <- scope t
                      (t',r) <- infer t1
                      isSort r
                      addGlobal x (Axiom t')

processDef :: (TCGlobalMonad gm) => Name -> Maybe A.Expr -> A.Expr -> gm ()
processDef x (Just t) u = do t1 <- scope t
                             (t', r) <- infer t1
                             isSort r
                             u1 <- scope u
                             u' <- check u1 t'
                             addGlobal x (Def t' u')
processDef x Nothing u = do u1 <- scope u
                            (u', r) <- infer u1
                            addGlobal x (Def r u')

addGlobal :: (TCGlobalMonad gm) => Name -> Global -> gm ()
addGlobal x g = do mWhen (definedName x) $ alreadyDefined x
                   extendName x g