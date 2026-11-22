{-# LANGUAGE OverloadedStrings #-}

-- | JSON game records. D09.
--
-- A record is everything needed to replay a game:
--
-- > { "version": 1, "rules": "pylos-owner-2026-11-22",
-- >   "white": "random", "black": "random",
-- >   "result": "white", "moves": ["a11", "a12", "a11-b11 x b11"], "plies": 3 }
--
-- @result@ is @"white"@ or @"black"@ (the winner), @"capped"@ (stopped by a
-- ply bound, D12) or @null@ (unfinished). The @version@ field is an
-- addition to D09's list so the format can change safely later
-- (@BACKWARD_COMPATIBILITY.md@). See @docs/adr/0017-record-and-golden-formats.md@.
module Pylos.Reference.Record
  ( GameRecord (..)
  , RecordResult (..)
  , rulesId
  , recordFromPlayout
  , replay
  , encodeRecord
  , decodeRecord
  ) where

import Data.Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T

import Pylos.Reference.Board
import Pylos.Reference.Move (Move)
import Pylos.Reference.Notation
import Pylos.Reference.Playout (Outcome (..), PlayoutResult (..))
import Pylos.Reference.Rules (winner)

-- | The name of the rule set this engine implements (R03–R08 as confirmed
-- by the owner on 2026-11-22).
rulesId :: Text
rulesId = "pylos-owner-2026-11-22"

-- | How a recorded game ended.
data RecordResult
  = ResultWinner Colour
  | ResultCapped
  | ResultUnfinished
  deriving (Eq, Show)

-- | A game record. D09.
data GameRecord = GameRecord
  { recordVersion :: Int
  , recordRules :: Text
  , recordWhite :: Text
  , recordBlack :: Text
  , recordResult :: RecordResult
  , recordMoves :: [Text]
  , recordPlies :: Int
  }
  deriving (Eq, Show)

instance ToJSON RecordResult where
  toJSON (ResultWinner White) = String "white"
  toJSON (ResultWinner Black) = String "black"
  toJSON ResultCapped = String "capped"
  toJSON ResultUnfinished = Null

instance FromJSON RecordResult where
  parseJSON Null = pure ResultUnfinished
  parseJSON (String "white") = pure (ResultWinner White)
  parseJSON (String "black") = pure (ResultWinner Black)
  parseJSON (String "capped") = pure ResultCapped
  parseJSON v = fail ("unknown result: " ++ show v)

instance ToJSON GameRecord where
  toJSON r =
    object
      [ "version" .= recordVersion r
      , "rules" .= recordRules r
      , "white" .= recordWhite r
      , "black" .= recordBlack r
      , "result" .= recordResult r
      , "moves" .= recordMoves r
      , "plies" .= recordPlies r
      ]

instance FromJSON GameRecord where
  parseJSON = withObject "GameRecord" $ \o ->
    GameRecord
      <$> o .: "version"
      <*> o .: "rules"
      <*> o .: "white"
      <*> o .: "black"
      <*> o .:? "result" .!= ResultUnfinished
      <*> o .: "moves"
      <*> o .: "plies"

-- | Write a record as JSON.
encodeRecord :: GameRecord -> BL.ByteString
encodeRecord = encode

-- | Read a record from JSON.
decodeRecord :: BL.ByteString -> Either String GameRecord
decodeRecord = eitherDecode

-- | Make a record from a playout result and the moves it played.
recordFromPlayout :: Text -> Text -> PlayoutResult -> [Move] -> GameRecord
recordFromPlayout w b res ms =
  GameRecord
    { recordVersion = 1
    , recordRules = rulesId
    , recordWhite = w
    , recordBlack = b
    , recordResult = case res of
        Finished (Winner c) _ -> ResultWinner c
        Capped _ -> ResultCapped
    , recordMoves = map (T.pack . renderMove) ms
    , recordPlies = length ms
    }

-- | Replay a record from the start position, checking every move. Returns
-- the final position and the result it implies: a winner if the game is
-- over (R05), otherwise unfinished. (A capped game looks unfinished: the
-- cap is not part of the rules.)
replay :: GameRecord -> Either String (Position, RecordResult)
replay r = do
  ms <- parseMoves (map T.unpack (recordMoves r))
  final <- playMoves startPosition ms
  pure (final, maybe ResultUnfinished ResultWinner (winner final))
