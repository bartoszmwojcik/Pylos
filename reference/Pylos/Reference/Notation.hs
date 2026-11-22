-- | Writing and reading squares and moves as text. D09.
--
-- * A square is @<level><row><col>@, from @a11@ to @d11@.
-- * A placement is the square: @a23@.
-- * A raise is two squares joined by a dash: @a11-b22@.
-- * Take-backs are appended after @x@: @a23 x a23 a24@.
--
-- 'renderMove' always writes take-backs in canonical (sorted) order, so a
-- move has exactly one written form. 'parseMove' accepts either order.
module Pylos.Reference.Notation
  ( renderPos
  , parsePos
  , renderAction
  , renderMove
  , parseMove
  , parseMoves
  , playMoves
  ) where

import Data.Char (isDigit)
import qualified Data.Set as Set

import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Rules (isLegal, applyMove)

-- | Write a square, e.g. @a23@. D09.
renderPos :: Pos -> String
renderPos (Pos l r c) = levelChar l : show r ++ show c

-- | Read a square. D09. The error names the bad token.
parsePos :: String -> Either String Pos
parsePos [lc, rc, cc]
  | Just l <- lookup lc levelChars
  , isDigit rc
  , isDigit cc
  , Just p <- mkPos l (read [rc]) (read [cc]) =
      Right p
  where
    levelChars = [(levelChar l, l) | l <- [minBound .. maxBound]]
parsePos tok = Left (badToken tok "not a square (expected a11 .. d11)")

-- | Write an action: @a23@ or @a11-b22@. D09.
renderAction :: Action -> String
renderAction (Place p) = renderPos p
renderAction (Raise from to) = renderPos from ++ "-" ++ renderPos to

-- | Write a move. D09.
renderMove :: Move -> String
renderMove (Move a t)
  | Set.null t = renderAction a
  | otherwise = renderAction a ++ " x " ++ unwords (map renderPos (Set.toAscList t))

-- | Read a move. D09.
--
-- This checks the form of the text, not whether the move is legal in some
-- position. It does reject a raise that does not go up a level (R03), since
-- such a move can never be legal. Every error names the bad token.
parseMove :: String -> Either String Move
parseMove text = case words text of
  [] -> Left "empty move"
  (act : rest) -> do
    a <- parseAction act
    t <- parseTakeBack rest
    pure (Move a t)

parseAction :: String -> Either String Action
parseAction tok = case break (== '-') tok of
  (p, "") -> Place <$> parsePos p
  (f, '-' : t) -> do
    from <- either (const (Left (badToken tok "not a raise (expected e.g. a11-b22)"))) Right (parsePos f)
    to <- either (const (Left (badToken tok "not a raise (expected e.g. a11-b22)"))) Right (parsePos t)
    if posLevel to > posLevel from
      then Right (Raise from to)
      else Left (badToken tok "a raise must go to a higher level")
  _ -> Left (badToken tok "not a move")

parseTakeBack :: [String] -> Either String (Set.Set Pos)
parseTakeBack [] = Right Set.empty
parseTakeBack ("x" : toks)
  | null toks = Left (badToken "x" "no take-back squares follow it")
  | length toks > 2 = Left (badToken (unwords toks) "at most 2 balls can be taken back")
  | otherwise = do
      ps <- traverse parsePos toks
      let set = Set.fromList ps
      if Set.size set == length ps
        then Right set
        else Left (badToken (unwords toks) "the same square is taken back twice")
parseTakeBack (tok : _) = Left (badToken tok "expected \"x\" before take-backs")

-- | Read a list of moves, one per string.
parseMoves :: [String] -> Either String [Move]
parseMoves = traverse parseMove

-- | Play moves one after another from a position, checking each one. The
-- error names the first illegal move and its ply number (1-based).
playMoves :: Position -> [Move] -> Either String Position
playMoves = go 1
  where
    go :: Int -> Position -> [Move] -> Either String Position
    go _ pos [] = Right pos
    go n pos (m : ms)
      | isLegal m pos = go (n + 1) (applyMove m pos) ms
      | otherwise =
          Left ("illegal move at ply " ++ show n ++ ": \"" ++ renderMove m ++ "\"")

badToken :: String -> String -> String
badToken tok why = "bad token \"" ++ tok ++ "\": " ++ why
