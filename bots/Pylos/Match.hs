-- | Playing bots against each other (S3): one game, or a match of many.
--
-- The engine has no draw rule (R06). The match runner owns that policy
-- (D12): a game that reaches the ply cap is a draw.
module Pylos.Match
  ( GameResult (..)
  , Game (..)
  , playGame
  , gameRecord
  , MatchScore (..)
  , scoreGame
  ) where

import qualified Data.Text as T

import qualified Pylos.Bitboard as B
import Pylos.Bot
import Pylos.Reference.Board (Colour (..))
import qualified Pylos.Reference.Playout as R
import Pylos.Reference.Random (Gen)
import Pylos.Reference.Record (GameRecord, recordFromPlayout)

-- | How a game ended.
data GameResult
  = -- | The winner (R05).
    WonBy Colour
  | -- | The ply cap was reached: a draw by the runner's policy (D12).
    DrawByCap
  deriving (Eq, Show)

-- | A finished game: the moves in order and the result.
data Game = Game
  { gameMoves :: [B.BMove]
  , gameResult :: GameResult
  }

-- | Play one game from the start: White's bot, Black's bot, the ply cap,
-- and the generator that makes it reproducible.
playGame :: BotSpec -> BotSpec -> Int -> Gen -> Game
playGame white black cap = go 0 [] B.startPosition
  where
    go plies acc p g
      | Just w <- B.winner p = Game (reverse acc) (WonBy w)
      | plies >= cap = Game (reverse acc) DrawByCap
      | otherwise =
          let bot = if B.bWhiteToMove p then white else black
           in case chooseMove bot g p of
                Nothing -> Game (reverse acc) DrawByCap -- unreachable (R05)
                Just (m, g') -> go (plies + 1) (m : acc) (B.applyMove m p) g'

-- | The game as a D09 record. A draw by the cap is stored as @"capped"@.
gameRecord :: BotSpec -> BotSpec -> Game -> GameRecord
gameRecord white black (Game ms res) =
  recordFromPlayout
    (T.pack (renderSpec white))
    (T.pack (renderSpec black))
    playoutResult
    (map B.toRefMove ms)
  where
    playoutResult = case res of
      WonBy c -> R.Finished (R.Winner c) (length ms)
      DrawByCap -> R.Capped (length ms)

-- | Wins, losses and draws for one bot of a match.
data MatchScore = MatchScore
  { wins :: !Int
  , losses :: !Int
  , draws :: !Int
  }
  deriving (Eq, Show)

instance Semigroup MatchScore where
  MatchScore a b c <> MatchScore x y z = MatchScore (a + x) (b + y) (c + z)

instance Monoid MatchScore where
  mempty = MatchScore 0 0 0

-- | The score of one game for the bot that played @colour@.
scoreGame :: Colour -> GameResult -> MatchScore
scoreGame _ DrawByCap = MatchScore 0 0 1
scoreGame colour (WonBy w)
  | w == colour = MatchScore 1 0 0
  | otherwise = MatchScore 0 1 0
