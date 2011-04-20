{

{-# OPTIONS_GHC -fno-warn-deprecated-flags
                -fno-warn-lazy-unlifted-bindings #-}
--| TODO
--
--  * Unicode support: see GHC lexer and Agda lexer (the latter seems simpler)

module Syntax.Lexer where

import Control.Monad.State

import Syntax.Tokens
import Syntax.Alex
import Syntax.ParseMonad
import Syntax.Position

}

$digit = 0-9
$alpha = [ a-z A-Z _ ]

@number = $digit+
@ident = $alpha [ $alpha $digit \' ]*

tokens :-

  $white+       ;

  -- One-line and nested comments
  "--"       { \_ _ -> skipOneLineComment }
  "{-"       { \_ _ -> skipNestedComment }


  -- Type without a number is a synonym of Type0. See Syntax.Tokens.ident
  -- This should be guaranteed since Alex process the action with the longest
  -- match. Type3 should match this rule, while Type<not a number> should match
  -- rule @ident below
  Type @number      { typeKeyword }

  \(          { symbol }
  \)          { symbol }
  "->"        { symbol }
  "=>"        { symbol }
  ","         { symbol }
  ":="        { symbol }
  "."         { symbol }
  ":"         { symbol }
  "::"        { symbol }
  "|"         { symbol }
  "+"         { symbol }
  "-"         { symbol }
  "++"        { symbol }
  "@"         { symbol }
  "<"         { symbol }
  ">"         { symbol }
  "["         { symbol }
  "]"         { symbol }

  @ident      { ident }

  @number     { number }
{

-- wraps the Lexer generated by alex into the monad Parser

lexToken :: Parser Token
lexToken =
  do s <- get
     case alexScan s 0 of  -- 0 is the state of the lexer. Not used now
       AlexEOF -> return TokEOF
       AlexError inp' -> parseErrorAt (lexPos s) ("Lexical error") -- rest of input ingnored at the moment
       AlexSkip inp' len -> put inp' >> lexToken
       AlexToken inp' len act ->
         do put inp'
            act (lexPos s) (take len (lexInput s))

lexer :: (Token -> Parser a) -> Parser a
lexer cont = lexToken >>= cont

-- | skip characters till a newline is found.
--   We use the fact that Parser = AlexInput
skipOneLineComment :: Parser Token
skipOneLineComment =
  do s <- get
     skip_ s
     lexToken
    where skip_ :: AlexInput -> Parser ()
          skip_ inp =
            case alexGetChar inp of
              Just ('\n', inp') -> put inp'
              Just (c   , inp') -> skip_ inp'
              Nothing           -> put inp

skipNestedComment :: Parser Token
skipNestedComment =
  do s <- get
     skip_ 1 s
     lexToken
    where
      skip_ :: Int -> AlexInput -> Parser ()
      skip_ 0 inp = put inp
      skip_ n (AlexInput { lexPos = p,
                           lexInput = ('{':'-':s) }) =
        skip_ (n + 1) (AlexInput { lexPos = advancePos p 2,
                                   lexInput = s,
                                   lexPrevChar = '-' })
      skip_ n (AlexInput { lexPos = p,
                           lexInput = ('-':'}':s) }) =
        skip_ (n - 1) (AlexInput { lexPos = advancePos p 2,
                                   lexInput = s,
                                   lexPrevChar = '}' })
      skip_ n inp =
        case alexGetChar inp of
          Just (c   , inp') -> skip_ n inp'
          Nothing           -> fail "Open nested comment"

}