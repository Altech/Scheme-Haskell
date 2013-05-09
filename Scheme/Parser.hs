module Scheme.Parser (
    parseDatum
  , parse
  ) where

import Control.Applicative ((<|>))
import Control.Monad (liftM)
import Text.Trifecta hiding (spaces)
import Text.Trifecta.Delta (Delta(Lines))

import Scheme.Internal

{- External representations
 ⟨Datum⟩ is what the read procedure (section 6.6.2) successfully parses. Note that any string that parses as an ⟨expression⟩ will also parse as a ⟨datum⟩.

   ⟨datum⟩ → ⟨simple datum⟩ | ⟨compound datum⟩ 
   ⟨simple datum⟩ → ⟨boolean⟩ | ⟨number⟩ | ⟨character⟩ | ⟨string⟩ | ⟨symbol⟩
   ⟨symbol⟩ → ⟨identifier⟩
   ⟨compound datum⟩ → ⟨list⟩ | ⟨vector⟩
   ⟨list⟩ −→ (⟨datum⟩*) | (⟨datum⟩+ . ⟨datum⟩) | ⟨abbreviation⟩
   ⟨abbreviation⟩ → ⟨abbrev prefix⟩ ⟨datum⟩ 
   ⟨abbrev prefix⟩ → ’ | ` | , | ,@
   ⟨vector⟩ → #(⟨datum⟩*)

-}

parseDatum :: Parser LispVal -- Especially, it returns subset of LispVal. (e.g. Procedure won't be returned.)
parseDatum = parseSimpleDatum <|> parseCompoundDatum

parseSimpleDatum :: Parser LispVal
parseSimpleDatum = parseBoolean <|> parseNumber <|> parseCharacter <|> parseString' <|> parseSymbol

parseCompoundDatum = parseList -- <|> parseVector

--- Symple Datum ... it is called ⟨self-evaluating⟩.
parseBoolean = (string "#t" <|> string "#f") >>= conv
  where conv bool = case bool of 
          "#t" -> return $ Bool True
          "#f" -> return $ Bool False

parseNumber = liftM Number $ decimal -- [TODO] support Hex, Oct, Bin and sign.

parseCharacter :: Parser LispVal
parseCharacter = liftM Character $ do -- [Full]
  string "#\\"
  (string "space" >> return ' ') <|> (string "newline" >> return '\n') <|> anyChar

parseString' = liftM String $ stringLiteral -- [TODO] Check exact syntax.

parseSymbol = liftM Symbol $ peculiarIdentifier <|> do
  first <- letter <|> specialInitial 
  rest <- many (letter <|> specialInitial <|> digit <|> specialSubsequent)  
  return $ first:rest
  where 
    specialInitial = oneOf "!$%&*/:<=>?^_~"
    specialSubsequent = oneOf "+-.@"
    peculiarIdentifier = string "+" <|> string "-" <|> string "..."

-- Compound Datum
parseList = try parseNormalList <|> parseDottedList <|> parseAbbreviation
  where parseNormalList = do 
          char '(' 
          ls <- sepBy parseDatum spaces
          char ')'
          return $ List ls
        parseDottedList = do
          char '(' 
          ls <- endBy parseDatum spaces -- [TODO] Check get one at least
          _last <- char '.' >> spaces >> parseDatum
          char ')'
          return $ case _last of 
            DottedList xs x -> DottedList (ls ++ xs) x
            List _last  -> List (ls ++ _last)
            obj -> DottedList ls obj
        parseAbbreviation = do
          sym <- parseAbbrevPrefix
          datum <- parseDatum
          return $ List [sym, datum]
        parseAbbrevPrefix = (string ",@" <|> string "'" <|> string "`" <|> string ",") >>= return . Symbol . lookupAbbrev
        abbrevs = [(",@", "unquote-splicing"),
                   ("'" , "quote"),
                   ("`" , "quasiquote"),
                   ("," , "unquote")]
        lookupAbbrev abbrev = case lookup abbrev abbrevs of Just sym -> sym

spaces = space >> skipMany space

-- For debug
parse :: Show a => Parser a -> String -> Result a
parse parser str = parseString parser (Lines 0 0 0 0) str
