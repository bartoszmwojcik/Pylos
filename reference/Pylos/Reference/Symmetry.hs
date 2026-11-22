-- | The 8 symmetries of the square board (4 rotations, each optionally
-- mirrored). The rules (R03–R08) treat all four sides of the pyramid alike,
-- so a symmetric position must have the same number of moves. The tests use
-- this as a check on the move generator.
module Pylos.Reference.Symmetry
  ( Symmetry
  , symmetries
  , transformPos
  , transformPosition
  ) where

import qualified Data.Map.Strict as Map

import Pylos.Reference.Board

-- | One of the 8 symmetries, numbered 0..7.
newtype Symmetry = Symmetry Int
  deriving (Eq, Show)

-- | All 8 symmetries. Number 0 is the identity.
symmetries :: [Symmetry]
symmetries = map Symmetry [0 .. 7]

-- | Move a square. Each level is turned or mirrored around its own centre,
-- which keeps every square above the same four supports.
transformPos :: Symmetry -> Pos -> Pos
transformPos (Symmetry k) (Pos l r c) = Pos l r' c'
  where
    n = levelSize l
    flipped = if k >= 4 then (r, n + 1 - c) else (r, c)
    (r', c') = iterate rot90 flipped !! (k `mod` 4)
    rot90 (x, y) = (y, n + 1 - x)

-- | Move every ball of a position.
transformPosition :: Symmetry -> Position -> Position
transformPosition s pos = pos {board = Map.mapKeys (transformPos s) (board pos)}
