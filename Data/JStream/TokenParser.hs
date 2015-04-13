{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}

module Data.JStream.TokenParser (
    Element(..)
  , ParseResult(..)
  , tokenParser
) where

import qualified Data.Text as T
import qualified Data.ByteString.Char8 as BS
import Data.Char (isSpace, isDigit, isDigit)
import Data.Text.Encoding (decodeUtf8)


data Element = ArrayBegin | ArrayEnd | ObjectBegin | ObjectEnd
               | ArrayKey T.Text
               | JString T.Text | JNumber Int | JBool Bool | JNull
               deriving (Show)

data ParseResult =  MoreData (BS.ByteString -> ParseResult)
                  | PartialResult Element ParseResult
                  | Failed

isBreakChar :: Char -> Bool
isBreakChar c = isSpace c || (c == '{') || (c == '[') || (c == '}') || (c == ']') || (c == ',')

ident :: BS.ByteString -> Element -> BS.ByteString -> Maybe ParseResult
ident name el input
  | BS.length name < BS.length input =
      if name `BS.isPrefixOf` input && isBreakChar (BS.index input (BS.length name))
        then Just $ PartialResult el (tokenParser (BS.drop (BS.length name) input))
        else Nothing
  | otherwise = Just $ moredata input tokenParser

moredata :: BS.ByteString -> (BS.ByteString -> ParseResult) -> ParseResult
moredata bl p = MoreData (p . BS.append bl)

parseSpecChar :: BS.ByteString -> BS.ByteString -> ParseResult
parseSpecChar start bl
  | BS.null bl = moredata "" (parseSpecChar start)
  | chr == '"' = slashchr '"'
  | chr == '\\' = slashchr '\\'
  | chr == '/' = slashchr '\\'
  | chr == 'b' = slashchr '\b'
  | chr == 'f' = slashchr '\f'
  | chr == 'n' = slashchr '\n'
  | chr == 'r' = slashchr '\r'
  | chr == 't' = slashchr '\t'
  -- TODO - unicode
  | otherwise = Failed
  where
    chr = BS.head bl
    slashchr c = parseString (start `BS.append` BS.singleton c) (BS.tail bl)

chooseKeyOrValue :: T.Text -> BS.ByteString -> ParseResult
chooseKeyOrValue text bl
  | BS.null bl = moredata "" (chooseKeyOrValue text)
  | chr == ':' = PartialResult (ArrayKey text) (tokenParser $ BS.tail bl)
  | otherwise = PartialResult (JString text) (tokenParser bl)
  where
    chr = BS.head bl


-- | Naparsuje string, ale po ukonceni stringu pocka, jestli neni ':', pak by to byl klic
parseString :: BS.ByteString -> BS.ByteString -> ParseResult
parseString start bl
  | BS.null bl = moredata "" (parseString start)
  | chr == '"' = chooseKeyOrValue (decodeUtf8 start) (BS.tail bl)
  | chr == '\\' = parseSpecChar start (BS.tail bl)
  | otherwise = parseString (BS.append start cont) rest
  where
    chr = BS.head bl
    (cont, rest) = BS.break (\c -> c == '"' || c == '\\' ) bl

tokenParser :: BS.ByteString -> ParseResult
tokenParser bl
  | BS.null bl = moredata "" tokenParser
  | isSpace chr = tokenParser (BS.dropWhile isSpace bl)
  | chr == '[' = partres ArrayBegin
  | chr == ']' = partres ArrayEnd
  | chr == '{' = partres ObjectBegin
  | chr == '}' = partres ObjectEnd
  | chr == ',' = tokenParser (BS.tail bl)
  | isDigit chr =
        let (start, rest) = BS.span isDigit bl
        in if | BS.null rest -> moredata bl tokenParser
              | otherwise -> PartialResult (JNumber $ read (BS.unpack start)) (tokenParser rest)
  | chr == '"' = parseString BS.empty (BS.tail bl)
  | Just res <- ident "true" (JBool True) bl = res
  | Just res <- ident "false" (JBool False) bl = res
  | Just res <- ident "null" JNull bl = res
  | otherwise = Failed
  where
    chr = BS.head bl
    partres elm = PartialResult elm (tokenParser $ BS.tail bl)