-- | The Pylos board: levels, squares, which squares rest on which, and the
-- position of a game (who owns which square, the reserves, whose turn it is).
--
-- Nothing in this module decides whether a move is legal. That lives in
-- "Pylos.Reference.Rules". This module only describes the shape of the board
-- (rule R08) and gives a way to print a position.
module Pylos.Reference.Board
  ( -- * Geometry (R08)
    Level (..)
  , levelSize
  , levelChar
  , Pos (..)
  , mkPos
  , allPositions
  , positionsOn
  , supports
  , restingOn
    -- * Players
  , Colour (..)
  , opponent
  , ballsPerPlayer
    -- * Positions
  , Board
  , Position (..)
  , startPosition
  , reserveOf
  , ballsOnBoard
  , renderPosition
  ) where

import Data.List (intercalate)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

-- | The four levels of the pyramid, from the bottom (@A@) to the apex (@D@).
--
-- R08: level a is 4×4, b is 3×3, c is 2×2 and d is a single square.
data Level = A | B | C | D
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The width (and height) of a level. R08.
levelSize :: Level -> Int
levelSize A = 4
levelSize B = 3
levelSize C = 2
levelSize D = 1

-- | The letter a level is written with in the notation (D09).
levelChar :: Level -> Char
levelChar A = 'a'
levelChar B = 'b'
levelChar C = 'c'
levelChar D = 'd'

-- | One square of the board: a level plus a 1-based row and column.
--
-- The derived 'Ord' (level first, then row, then column) is the canonical
-- order used everywhere a list of squares or moves must be sorted.
data Pos = Pos
  { posLevel :: !Level
  , posRow :: !Int
  , posCol :: !Int
  }
  deriving (Eq, Ord, Show)

-- | Build a square, or 'Nothing' when the row or column is off the level.
mkPos :: Level -> Int -> Int -> Maybe Pos
mkPos l r c
  | inRange r && inRange c = Just (Pos l r c)
  | otherwise = Nothing
  where
    inRange x = x >= 1 && x <= levelSize l

-- | The squares of one level, row by row.
positionsOn :: Level -> [Pos]
positionsOn l = [Pos l r c | r <- [1 .. n], c <- [1 .. n]]
  where
    n = levelSize l

-- | All 30 squares (16 + 9 + 4 + 1), in canonical order. R08.
allPositions :: [Pos]
allPositions = concatMap positionsOn [minBound .. maxBound]

-- | The squares a square rests on. R08.
--
-- A square on level a rests on the table, so it has no supports. Square
-- (r, c) on any higher level sits in the hollow between the four squares
-- (r, c), (r, c+1), (r+1, c) and (r+1, c+1) of the level below.
supports :: Pos -> [Pos]
supports (Pos A _ _) = []
supports (Pos l r c) =
  [Pos (pred l) r' c' | r' <- [r, r + 1], c' <- [c, c + 1]]

-- | The squares that rest on a square: the inverse of 'supports'.
--
-- Used to decide whether a ball is free (R04): a ball is free when none of
-- these squares holds a ball.
restingOn :: Pos -> [Pos]
restingOn p = [q | q <- allPositions, p `elem` supports q]

-- | The two players. White moves first.
data Colour = White | Black
  deriving (Eq, Ord, Show, Enum, Bounded)

-- | The other player.
opponent :: Colour -> Colour
opponent White = Black
opponent Black = White

-- | Each player starts with 15 balls in reserve. R08.
ballsPerPlayer :: Int
ballsPerPlayer = 15

-- | Which squares hold a ball, and whose. A missing key means empty.
type Board = Map Pos Colour

-- | Everything needed to continue a game. There is no move history: the
-- engine has no draw or repetition rule (R06), so the past does not matter.
data Position = Position
  { board :: !Board
  , whiteReserve :: !Int
  , blackReserve :: !Int
  , toMove :: !Colour
  }
  deriving (Eq, Ord, Show)

-- | The empty board, both reserves full, White to move. R08.
startPosition :: Position
startPosition = Position Map.empty ballsPerPlayer ballsPerPlayer White

-- | How many balls a player has not placed yet.
reserveOf :: Colour -> Position -> Int
reserveOf White = whiteReserve
reserveOf Black = blackReserve

-- | How many balls of a colour are on the board.
ballsOnBoard :: Colour -> Position -> Int
ballsOnBoard col = Map.size . Map.filter (== col) . board

-- | A multi-line text picture of a position. Each level is drawn as a grid,
-- side by side, row 1 at the top. @W@ and @B@ are the balls, @.@ is empty.
--
-- > Level a   Level b  Level c  Level d
-- > W . . .   . . .    . .      .
-- > . B . .   . . .    . .
-- > . . . .   . . .
-- > . . . .
-- > White to move. Reserve: White 14, Black 14.
renderPosition :: Position -> String
renderPosition pos = unlines (header : gridLines ++ [footer])
  where
    levels = [minBound .. maxBound] :: [Level]
    width l = 2 * levelSize l + 1
    pad n s = s ++ replicate (n - length s) ' '
    header =
      trimEnd (concat [pad (max 9 (width l)) ("Level " ++ [levelChar l]) | l <- levels])
    gridLines =
      [ trimEnd (concat [pad (max 9 (width l)) (rowText l r) | l <- levels])
      | r <- [1 .. 4]
      ]
    rowText l r
      | r > levelSize l = ""
      | otherwise = unwords [cell (Pos l r c) | c <- [1 .. levelSize l]]
    cell p = case Map.lookup p (board pos) of
      Nothing -> "."
      Just White -> "W"
      Just Black -> "B"
    footer =
      show (toMove pos)
        ++ " to move. Reserve: "
        ++ intercalate
          ", "
          ["White " ++ show (whiteReserve pos), "Black " ++ show (blackReserve pos)]
        ++ "."
    trimEnd = reverse . dropWhile (== ' ') . reverse
