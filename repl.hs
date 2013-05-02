module Main where
import System.Environment
import Text.Parsec hiding (spaces)
import Control.Monad (liftM)
import Data.Char (chr)
import Numeric (readOct, readHex)

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool

-- Show
showVal :: LispVal -> String
showVal (String contents) = "\"" ++ contents ++ "\""
showVal (Atom name) = name
showVal (Number contents) = show contents
showVal (Bool True) = "#t"
showVal (Bool False) = "#f"
showVal (List contents) = "(" ++ unwordsList contents ++ ")"
showVal (DottedList hd tl) = "(" ++ unwordsList hd ++ " . " ++ showVal tl ++ ")"

unwordsList :: [LispVal] -> String
unwordsList = unwords . map showVal

instance Show LispVal where show = showVal

-- Parser

symbol :: Parsec String u Char
symbol = oneOf "!#$%&|*+-/:<=>?@^_~"

spaces :: Parsec String u ()
spaces = skipMany1 space

parseStringEscapedUnicode :: Parsec String u Char
parseStringEscapedUnicode = liftM (chr . read) $ char '\\' >> count 4 digit

parseStringEscapedASCII :: Parsec String u Char
parseStringEscapedASCII = liftM convert $ char '\\' >> noneOf ""
  where
    controlChars =  [('n','\n'),
                     ('t','\t'),
                     ('r','\r'),
                     ('0','\0')]
    convert c = case lookup c controlChars of
      Just v -> v
      Nothing -> c

parseString :: Parsec String u LispVal
parseString = do
  char '"'
  str <- many $ (try parseStringEscapedUnicode) <|> (try parseStringEscapedASCII) <|> noneOf "\""
  char '"'
  return $ String str

parseAtom :: Parsec String u LispVal
parseAtom = do
  first <- letter <|> symbol
  rest <- many (letter <|> digit <|> symbol)
  let atom = first:rest
  return $ case atom of
    "#t" -> Bool True
    "#f" -> Bool False
    _    -> Atom atom

parseNumberDecimal :: Parsec String u LispVal
parseNumberDecimal = liftM (Number . read) $ (many1 digit) <|> (string "#d" >> many1 digit)

parseNumberHex :: Parsec String u LispVal
parseNumberHex = liftM (Number . fst . head . readHex) $ string "#x" >> many1 hexadecimal
  where hexadecimal = digit <|> oneOf "abcdef"

parseNumberOct :: Parsec String u LispVal
parseNumberOct = liftM (Number . fst . head . readOct) $ string "#o" >> many1 octal
  where octal = oneOf "01234567"

parseNumberBin :: Parsec String u LispVal
parseNumberBin = liftM (Number . readBin . reverse) $ string "#b" >> many1 binary
  where binary = oneOf "01"
        readBin str = case str of
          [] -> 0
          (b:bs) -> read [b] + 2 * readBin bs

parseNumber :: Parsec String u LispVal
parseNumber = (try parseNumberDecimal) <|> (try parseNumberHex) <|> (try parseNumberOct) <|> (try parseNumberBin)

parseList :: Parsec String u LispVal
parseList = liftM List $ sepBy parseExpr spaces

parseDottedList :: Parsec String u LispVal
parseDottedList = do
  hd <- endBy parseExpr spaces
  tl <- char '.' >> spaces >> parseExpr
  return $ DottedList hd tl

parseQuoted :: Parsec String u LispVal
parseQuoted = do
  char '\''
  x <- parseExpr
  return $ List [Atom "quote",x]

parseExpr :: Parsec String u LispVal
parseExpr = parseNumber <|> parseAtom <|> parseString <|> parseQuoted <|> do
  char '('
  x <- try parseList <|> parseDottedList
  char ')'
  return x

readExpr :: String -> LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> String $ "No match: " ++ show err
    Right val -> val
    
-- Evaluation
eval :: LispVal -> LispVal
eval val@(String _) = val
eval val@(Number _) = val
eval val@(Bool _)   = val
eval (List [Atom "quote", val]) = val
eval (List (Atom func : args)) = apply func $ map eval args

apply :: String -> [LispVal] -> LispVal
apply func args = maybe (Bool False) ($ args) $ lookup func primitives

primitives :: [(String, [LispVal] -> LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem)]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> LispVal
numericBinop op params = Number $ foldl1 op $ map unpackNum params

unpackNum :: LispVal -> Integer
unpackNum (Number n) = n
unpackNum (String n) = let parsed = reads n in
  if null parsed
  then 0
  else fst $ parsed !! 0
unpackNum (List [n]) = unpackNum n
unpackNum _ = 0
                     

main :: IO ()
main = getArgs >>= print . eval . readExpr . head
