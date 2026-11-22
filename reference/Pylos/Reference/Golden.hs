{-# LANGUAGE OverloadedStrings #-}

-- | Golden values: perft counts and seeded playout outcomes computed by the
-- reference engine and frozen in files under @golden/@. D11.
--
-- The bitboard engine (S2) must reproduce every value. Perft checks move
-- generation; the playouts also check how games end, which perft does not.
-- The files change only through a deliberate, explained regeneration
-- (@CODE_REVIEW.md@), never by hand.
module Pylos.Reference.Golden
  ( -- * Perft
    GoldenPerft (..)
  , goldenPositions
  , computeGoldenPerft
    -- * Playouts
  , GoldenPlayout (..)
  , playoutSeeds
  , playoutBound
  , computeGoldenPlayout
  , playoutResultText
  ) where

import Data.Aeson
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)

import Pylos.Reference.Board
import Pylos.Reference.Notation
import Pylos.Reference.Perft (perft)
import Pylos.Reference.Playout
import Pylos.Reference.Random (mkGen)

-- | Perft values for one position, given as the moves that reach it from
-- the start. @goldenPerft !! (d - 1)@ is perft at depth @d@.
data GoldenPerft = GoldenPerft
  { goldenName :: Text
  , goldenMoves :: [Text]
  , goldenPerft :: [Integer]
  }
  deriving (Eq, Show)

instance ToJSON GoldenPerft where
  toJSON g =
    object ["name" .= goldenName g, "moves" .= goldenMoves g, "perft" .= goldenPerft g]

instance FromJSON GoldenPerft where
  parseJSON = withObject "GoldenPerft" $ \o ->
    GoldenPerft <$> o .: "name" <*> o .: "moves" <*> o .: "perft"

-- | The positions whose perft is frozen, with the depth to go to.
--
-- The start position, plus fixed mid-game positions chosen to exercise
-- each rule: a completed square, a completed row, raises, and take-backs
-- that free another ball.
goldenPositions :: [(Text, [Text], Int)]
goldenPositions =
  [ ("start", [], 6)
  , -- White completes the square a11 a12 a21 a22 and takes back a11.
    ( "square-completed"
    , ["a11", "a33", "a12", "a34", "a21", "a43", "a22 x a11", "a44"]
    , 4
    )
  , -- White completes the row a11..a14 on level a (D14) and takes nothing back.
    ( "row-completed"
    , ["a11", "a21", "a12", "a22", "a13", "a23", "a14"]
    , 5
    )
  , -- A mixed 2x2 supports b11, so White can raise a33 onto it (R03).
    ( "raise-available"
    , ["a11", "a12", "a21", "a22", "a33", "a44"]
    , 5
    )
  , -- Level a is nearly full and level b has started: raises, squares on b,
    -- and take-backs that free a ball beneath (R04) are all possible.
    ( "crowded"
    , [ "a11", "a12", "a13", "a14", "a21", "a22", "a23", "a24"
      , "a31", "a32", "a33", "a34", "b11", "b12", "b21", "a41"
      ]
    , 4
    )
  ]

-- | Compute the golden perft values for one entry of 'goldenPositions'.
computeGoldenPerft :: (Text, [Text], Int) -> Either String GoldenPerft
computeGoldenPerft (name, moves, depth) = do
  ms <- parseMoves (map T.unpack moves)
  pos <- playMoves startPosition ms
  pure (GoldenPerft name moves [perft d pos | d <- [1 .. depth]])

-- | The outcome of one seeded playout from the start position.
data GoldenPlayout = GoldenPlayout
  { gpSeed :: Word64
  , gpBound :: Int
  , gpResult :: Text
  , gpPlies :: Int
  }
  deriving (Eq, Show)

instance ToJSON GoldenPlayout where
  toJSON g =
    object
      ["seed" .= gpSeed g, "bound" .= gpBound g, "result" .= gpResult g, "plies" .= gpPlies g]

instance FromJSON GoldenPlayout where
  parseJSON = withObject "GoldenPlayout" $ \o ->
    GoldenPlayout <$> o .: "seed" <*> o .: "bound" <*> o .: "result" <*> o .: "plies"

-- | The seeds of the frozen playouts.
playoutSeeds :: [Word64]
playoutSeeds = [1 .. 200]

-- | The ply bound of the frozen playouts.
playoutBound :: Int
playoutBound = 300

-- | @"white"@, @"black"@ or @"capped"@, and the number of plies played.
playoutResultText :: PlayoutResult -> (Text, Int)
playoutResultText (Finished (Winner White) n) = ("white", n)
playoutResultText (Finished (Winner Black) n) = ("black", n)
playoutResultText (Capped n) = ("capped", n)

-- | Run one seeded playout from the start position.
computeGoldenPlayout :: Word64 -> GoldenPlayout
computeGoldenPlayout seed = GoldenPlayout seed playoutBound res plies
  where
    (res, plies) = playoutResultText (playout playoutBound (mkGen seed) startPosition)
