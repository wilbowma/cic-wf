{-# LANGUAGE PackageImports, FlexibleInstances, TypeSynonymInstances,
  GeneralizedNewtypeDeriving, FlexibleContexts, FunctionalDependencies,
  MultiParamTypeClasses,
  CPP
  #-}

module Kernel.Case where

#include "../undefined.h"
import Utils.Impossible

import Control.Exception
import Control.Monad.Reader
import Control.Monad.Error

import Data.Function

import Syntax.Internal hiding (lift)
import Syntax.Internal as I
import Syntax.Common
import Syntax.Position
import qualified Syntax.Abstract as A
import Kernel.Conversion
import Kernel.TCM
import Kernel.Whnf
import {-# SOURCE #-} Kernel.TypeChecking


instance Infer A.CaseExpr (Term, Type) where
  infer (A.CaseExpr r arg Nothing Nothing Nothing (Just ret) branches) =
    do (arg', tpArg) <- infer arg
       tpArg' <- whnf tpArg
       (nmInd, (pars, inds)) <- getInductiveType tpArg
       Inductive tpPars tpInds sortInd _ <- getGlobal nmInd
       let tpArgGen = buildApp (Ind nmInd) (pars ++ dom tpInds)
       (ret', tpRet) <- infer ret
       checkReturnType tpRet (tpInds ++ [Bind (Id "x") tpArgGen])
       branches' <- checkBranches nmInd ret' pars branches
       let tpCase = buildApp ret' $ inds ++ [arg']
       tpCase' <- whnf tpCase
       return (Case $ CaseTerm arg' nmInd ret' branches', tpCase')
         where
           getInductiveType t =
             do t' <- whnf t
                case t' of
                  App (Ind i) args ->
                    do Inductive tpPars _ _ _ <- getGlobal i -- matching should not fail
                       return (i, splitAt (length tpPars) args)
                  Ind i            -> return (i, ([], []))
                  _                -> error $ "case 0. not inductive type " ++ show t
           checkReturnType t bs =
             do t' <- whnf t
                case t' of
                  Pi bs' u -> do b <- conversion bs bs'
                                 unless b $ error "case 1"
                                 _ <- isSort u
                                 return ()
                  _        -> error "case 2"


-- | 'checkBranches' @nmInd tpRet pars branches@ typechecks @branches@, where
--
--   * @nmInd@ is the name of the inductive type
--   * @tpRet@ is the return type of the whole case
--   * @pars@ are the parameters of the inductive type, to be applied in all the
--     expressions
--   * @branches@ is the list of branches to typecheck
--
--   We assume that all branches belong to the same inductive type (this is
--   ensured by the scope checker).
checkBranches :: (MonadTCM tcm) =>
                 Name -> Type -> [Term] -> [A.Branch] -> tcm [Branch]
checkBranches nmInd tpRet pars bs = check_ bs
  where
    check_ [] = return []
    check_ (A.Branch r nmConstr idConstr nmArgs body : bs) =
      do (Constructor _ _ tpPars tpArgs inds) <- getGlobal nmConstr
         -- type of branch = Π Δ_i *. P us_i * (C ps dom(Δ_i))
         let tpArgs' = renameBinds (foldr subst tpArgs pars) nmArgs
             inds'   = foldr subst inds pars
             constr  = Constr nmConstr (nmInd, idConstr) pars (dom tpArgs')
             tpBranch = buildApp tpRet (inds' ++ [constr])
         body' <- local (reverse tpArgs'++) $ check body tpBranch
         bs' <- check_ bs
         return $ Branch nmConstr idConstr nmArgs body' : bs'