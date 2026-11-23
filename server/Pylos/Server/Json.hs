{-# LANGUAGE OverloadedStrings #-}

-- | The JSON shapes of @docs/web-protocol.md@.
module Pylos.Server.Json
  ( positionJson
  , moveEventJson
  , resultJson
  , colourText
  ) where

import Data.Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import qualified Pylos.Bitboard as B
import Pylos.Match (GameResult (..))
import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Notation (renderMove, renderPos)

-- | @"white"@ or @"black"@.
colourText :: Colour -> Text
colourText White = "white"
colourText Black = "black"

-- | A position: the occupied squares, both reserves, whose turn it is.
positionJson :: B.BPosition -> Value
positionJson bp =
  object
    [ "squares"
        .= object
          [Key.fromString (renderPos p) .= colourText c | (p, c) <- Map.toAscList (board pos)]
    , "whiteReserve" .= whiteReserve pos
    , "blackReserve" .= blackReserve pos
    , "toMove" .= colourText (toMove pos)
    ]
  where
    pos = B.toReference bp

-- | The data of a @move@ event: the move as text and as parts, who played
-- it, and the position after it.
moveEventJson :: Int -> Colour -> B.BMove -> B.BPosition -> Value
moveEventJson ply by bm after =
  object
    [ "ply" .= ply
    , "move" .= T.pack (renderMove m)
    , "action" .= actionJson (moveAction m)
    , "takeBack" .= map (T.pack . renderPos) (Set.toAscList (moveTakeBack m))
    , "by" .= colourText by
    , "position" .= positionJson after
    ]
  where
    m = B.toRefMove bm
    actionJson (Place p) =
      object ["kind" .= ("place" :: Text), "from" .= Null, "to" .= T.pack (renderPos p)]
    actionJson (Raise f t) =
      object ["kind" .= ("raise" :: Text), "from" .= T.pack (renderPos f), "to" .= T.pack (renderPos t)]

-- | @"white"@ / @"black"@ for a winner, @"capped"@ for a draw by the cap,
-- @null@ while the game runs.
resultJson :: Maybe GameResult -> Value
resultJson Nothing = Null
resultJson (Just (WonBy c)) = String (colourText c)
resultJson (Just DrawByCap) = String "capped"
