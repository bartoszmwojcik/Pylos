{-# LANGUAGE BangPatterns #-}

-- | The bitboard engine (S2, D05): the same rules as
-- "Pylos.Reference.Rules", written for speed.
--
-- The 30 squares are the bits 0..29 of a 'Word32':
--
-- > level a: bits  0..15   (row-major: a11 = 0, a12 = 1, ..., a44 = 15)
-- > level b: bits 16..24   (b11 = 16, ..., b33 = 24)
-- > level c: bits 25..28   (c11 = 25, ..., c22 = 28)
-- > level d: bit  29       (d11)
--
-- A position is one mask per colour. Every rule question becomes a few
-- bitwise operations against tables computed once from the reference
-- geometry: "is s supported?" is @supportMask s .&. occupied == supportMask s@,
-- "is s free?" is @aboveMask s .&. occupied == 0@. See
-- @docs/adr/0020-bitboard-representation.md@.
--
-- This engine is only trusted because it matches the reference engine on
-- the golden perft and playout files and on random positions (D05, D11).
module Pylos.Bitboard
  ( -- * Positions
    BPosition (..)
  , startPosition
  , fromReference
  , toReference
    -- * Squares
  , squareIndex
  , indexSquare
    -- * Moves
  , BMove (..)
  , legalMoves
  , applyMove
  , winner
  , ownAndOther
  , reserveToMove
  , freeOf
  , toRefMove
  , fromRefMove
    -- * Perft and playouts
  , perft
  , perftWith
  , divide
  , playout
  ) where

import Data.Array (Array, listArray)
import qualified Data.Array as Array
import Data.Array.Unboxed (UArray)
import qualified Data.Array.Unboxed as UArray
import Data.Bits
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word32)

import qualified Pylos.Reference.Board as R
import qualified Pylos.Reference.Move as R
import Pylos.Reference.Playout (Outcome (..), PlayoutResult (..))
import Pylos.Reference.Random (Gen, uniformIndex)
import qualified Pylos.Reference.Rules as R

-- ---------------------------------------------------------------------------
-- Squares and tables

-- | The bit of a reference square.
squareIndex :: R.Pos -> Int
squareIndex (R.Pos l r c) = levelBase l + (r - 1) * R.levelSize l + (c - 1)
  where
    levelBase R.A = 0
    levelBase R.B = 16
    levelBase R.C = 25
    levelBase R.D = 29

-- | The reference square of a bit (0..29).
indexSquare :: Int -> R.Pos
indexSquare i = squares Array.! i

squares :: Array Int R.Pos
squares = listArray (0, 29) R.allPositions

maskOf :: [R.Pos] -> Word32
maskOf = foldl' (\m p -> m .|. bit (squareIndex p)) 0

-- | The squares a square rests on (R08).
supportMask :: UArray Int Word32
supportMask = UArray.listArray (0, 29) [maskOf (R.supports p) | p <- R.allPositions]

-- | The squares resting on a square (R04: free means none is occupied).
aboveMask :: UArray Int Word32
aboveMask = UArray.listArray (0, 29) [maskOf (R.restingOn p) | p <- R.allPositions]

-- | Every square on a strictly higher level than this square (R03).
higherMask :: UArray Int Word32
higherMask =
  UArray.listArray
    (0, 29)
    [maskOf [q | q <- R.allPositions, R.posLevel q > R.posLevel p] | p <- R.allPositions]

-- | The shapes (R07) through each square, as masks.
shapeMasks :: Array Int [Word32]
shapeMasks =
  listArray (0, 29) [map (maskOf . R.shapeSquares) (R.shapesThrough p) | p <- R.allPositions]

allSquares :: Word32
allSquares = bit 30 - 1

-- | The set bits of a mask, lowest first.
bitsOf :: Word32 -> [Int]
bitsOf 0 = []
bitsOf m = countTrailingZeros m : bitsOf (m .&. (m - 1))

-- ---------------------------------------------------------------------------
-- Positions

-- | A position: one mask per colour, the reserves, and whose turn it is.
data BPosition = BPosition
  { bWhite :: !Word32
  , bBlack :: !Word32
  , bWhiteReserve :: !Int
  , bBlackReserve :: !Int
  , bWhiteToMove :: !Bool
  }
  deriving (Eq, Ord, Show)

-- | The start position.
startPosition :: BPosition
startPosition = fromReference R.startPosition

-- | Convert from the reference representation.
fromReference :: R.Position -> BPosition
fromReference p =
  BPosition
    { bWhite = maskOf [q | (q, R.White) <- Map.toList (R.board p)]
    , bBlack = maskOf [q | (q, R.Black) <- Map.toList (R.board p)]
    , bWhiteReserve = R.whiteReserve p
    , bBlackReserve = R.blackReserve p
    , bWhiteToMove = R.toMove p == R.White
    }

-- | Convert to the reference representation.
toReference :: BPosition -> R.Position
toReference p =
  R.Position
    { R.board =
        Map.fromList
          ( [(indexSquare i, R.White) | i <- bitsOf (bWhite p)]
              ++ [(indexSquare i, R.Black) | i <- bitsOf (bBlack p)]
          )
    , R.whiteReserve = bWhiteReserve p
    , R.blackReserve = bBlackReserve p
    , R.toMove = if bWhiteToMove p then R.White else R.Black
    }

-- ---------------------------------------------------------------------------
-- Moves

-- | A move: @bmFrom@ is the origin bit of a raise, or -1 for a placement;
-- @bmTo@ the target bit; @bmTakeBack@ the take-back balls as a mask (D08:
-- a mask is a set, so order cannot matter).
data BMove = BMove
  { bmFrom :: !Int
  , bmTo :: !Int
  , bmTakeBack :: !Word32
  }
  deriving (Eq, Ord, Show)

-- | Convert to a reference move.
toRefMove :: BMove -> R.Move
toRefMove (BMove from to tb) = R.Move action (Set.fromList (map indexSquare (bitsOf tb)))
  where
    action
      | from < 0 = R.Place (indexSquare to)
      | otherwise = R.Raise (indexSquare from) (indexSquare to)

-- | Convert from a reference move.
fromRefMove :: R.Move -> BMove
fromRefMove (R.Move a tb) = case a of
  R.Place p -> BMove (-1) (squareIndex p) mask
  R.Raise f t -> BMove (squareIndex f) (squareIndex t) mask
  where
    mask = maskOf (Set.toList tb)

-- | The masks of the player to move and of the opponent.
ownAndOther :: BPosition -> (Word32, Word32)
ownAndOther p
  | bWhiteToMove p = (bWhite p, bBlack p)
  | otherwise = (bBlack p, bWhite p)

-- | The reserve of the player to move.
reserveToMove :: BPosition -> Int
reserveToMove p = if bWhiteToMove p then bWhiteReserve p else bBlackReserve p

-- | Empty squares whose supports are all occupied (R08).
supportedEmpty :: Word32 -> Word32
supportedEmpty occ = go 0 (allSquares .&. complement occ)
  where
    go !acc 0 = acc
    go !acc m =
      let i = countTrailingZeros m
          s = supportMask UArray.! i
          acc' = if s .&. occ == s then acc .|. bit i else acc
       in go acc' (m .&. (m - 1))

-- | The balls of a mask with nothing resting on them (R04), given all
-- occupied squares.
freeOf :: Word32 -> Word32 -> Word32
freeOf balls occ = go 0 balls
  where
    go !acc 0 = acc
    go !acc m =
      let i = countTrailingZeros m
          acc' = if aboveMask UArray.! i .&. occ == 0 then acc .|. bit i else acc
       in go acc' (m .&. (m - 1))

-- | Does the ball on @to@ complete one of the mover's shapes (R07)?
completes :: Int -> Word32 -> Bool
completes to own = any (\s -> s .&. own == s) (shapeMasks Array.! to)

-- | The take-back masks after a shape (R07, R04, D08): none, any one free
-- own ball, any two free own balls, or a free ball plus a ball it frees.
takeBacks :: Word32 -> Word32 -> [Word32]
takeBacks own occ = 0 : singles ++ freePairs ++ freedPairs
  where
    free = freeOf own occ
    stuck = own .&. complement free
    fs = bitsOf free
    singles = map bit fs
    freePairs = [bit x .|. bit y | x <- fs, y <- fs, x < y]
    freedPairs =
      [ bit x .|. bit y
      | x <- fs
      , let occ' = clearBit occ x
      , y <- bitsOf stuck
      , aboveMask UArray.! y .&. occ' == 0
      ]

-- | All legal moves (R03, R05, R07, R08, D08), in no particular order.
legalMoves :: BPosition -> [BMove]
legalMoves p
  | reserveToMove p == 0 = []
  | otherwise = placements ++ raises
  where
    (own, other) = ownAndOther p
    occ = own .|. other
    placements =
      [ m
      | to <- bitsOf (supportedEmpty occ)
      , m <- withTakeBacks (-1) to (setBit own to) (setBit occ to)
      ]
    raises =
      [ m
      | from <- bitsOf (freeOf own occ)
      , let occ' = clearBit occ from
            own' = clearBit own from
      , to <- bitsOf (supportedEmpty occ' .&. higherMask UArray.! from)
      , m <- withTakeBacks from to (setBit own' to) (setBit occ' to)
      ]
    withTakeBacks from to own' occ'
      | completes to own' = [BMove from to tb | tb <- takeBacks own' occ']
      | otherwise = [BMove from to 0]

-- | Play a move (not checked).
applyMove :: BMove -> BPosition -> BPosition
applyMove (BMove from to tb) p
  | bWhiteToMove p =
      p {bWhite = own', bWhiteReserve = bWhiteReserve p + delta, bWhiteToMove = False}
  | otherwise =
      p {bBlack = own', bBlackReserve = bBlackReserve p + delta, bWhiteToMove = True}
  where
    (own, _) = ownAndOther p
    moved = if from < 0 then setBit own to else setBit (clearBit own from) to
    own' = moved .&. complement tb
    delta = popCount tb - (if from < 0 then 1 else 0)

-- | The winner, if the player to move has an empty reserve (R05).
winner :: BPosition -> Maybe R.Colour
winner p
  | reserveToMove p /= 0 = Nothing
  | bWhiteToMove p = Just R.Black
  | otherwise = Just R.White

-- ---------------------------------------------------------------------------
-- Perft and playouts

-- | Perft (D08), counting the last level without playing it.
perft :: Int -> BPosition -> Integer
perft = perftWith legalMoves

-- | Perft with a given move generator. The tests use it to inject a bug and
-- check that the divide comparison finds it.
perftWith :: (BPosition -> [BMove]) -> Int -> BPosition -> Integer
perftWith gen = go
  where
    go n p
      | n <= 0 = 1
      | n == 1 = fromIntegral (length (gen p))
      | otherwise = sum' [go (n - 1) (applyMove m p) | m <- gen p]
    sum' = foldl' (+) 0

-- | Perft split by the first move.
divide :: Int -> BPosition -> [(BMove, Integer)]
divide n p = [(m, perft (n - 1) (applyMove m p)) | m <- legalMoves p]

-- | A bounded random playout (D12) that makes the same choices as
-- 'Pylos.Reference.Playout.playout' for the same seed: the moves are
-- sorted in reference order before one is picked.
playout :: Int -> Gen -> BPosition -> PlayoutResult
playout bound = go 0
  where
    go !plies g p
      | Just w <- winner p = Finished (Winner w) plies
      | plies >= bound = Capped plies
      | otherwise = case sortOn fst [(toRefMove m, m) | m <- legalMoves p] of
          [] -> Capped plies
          ms ->
            let (i, g') = uniformIndex (length ms) g
             in go (plies + 1) g' (applyMove (snd (ms !! i)) p)
