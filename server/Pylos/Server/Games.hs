{-# LANGUAGE OverloadedStrings #-}

-- | Live games (S4): each game runs in its own thread and broadcasts its
-- moves to every browser watching it.
--
-- The shared state lives in STM variables ('TVar'). A watcher takes the
-- current snapshot and subscribes to the event channel in /one/ atomic
-- step, so it can never miss a move or see one twice.
module Pylos.Server.Games
  ( Manager
  , newManager
  , NewGame (..)
  , startGame
  , LiveGame (..)
  , GameState (..)
  , Event (..)
  , lookupGame
  , listGames
  , watch
  , snapshotJson
  , summaryJson
  , maxRunning
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Exception (evaluate)
import Control.Monad (void)
import Data.Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import qualified Pylos.Bitboard as B
import Pylos.Bot
import Pylos.Match (GameResult (..))
import Pylos.Reference.Board (Colour (..))
import Pylos.Reference.Notation (renderMove)
import Pylos.Reference.Random (Gen, mkGen)
import Pylos.Server.Json

-- | A request for a new game, already validated.
data NewGame = NewGame
  { ngWhite :: BotSpec
  , ngBlack :: BotSpec
  , ngDelayMs :: Int
  , ngPlyCap :: Int
  }

-- | What changes while a game runs.
data GameState = GameState
  { gsMoves :: [B.BMove]
  -- ^ newest first
  , gsPosition :: B.BPosition
  , gsResult :: Maybe GameResult
  }

-- | What a watcher is told.
data Event
  = MoveEvent Value
  | EndEvent GameResult

-- | One game.
data LiveGame = LiveGame
  { lgId :: Int
  , lgSetup :: NewGame
  , lgState :: TVar GameState
  , lgEvents :: TChan Event
  -- ^ a broadcast channel: each watcher reads its own copy
  }

-- | All games of this server run.
data Manager = Manager
  { mGames :: TVar (Map.Map Int LiveGame)
  , mNextId :: TVar Int
  }

newManager :: IO Manager
newManager = Manager <$> newTVarIO Map.empty <*> newTVarIO 1

-- | At most this many games run at once, so the server stays responsive.
maxRunning :: Int
maxRunning = 8

-- | Start a game in a new thread. Fails when too many games are running.
startGame :: Manager -> NewGame -> IO (Either String Int)
startGame mgr ng = do
  initial <- newTVarIO (GameState [] B.startPosition Nothing)
  chan <- newBroadcastTChanIO
  result <- atomically $ do
    games <- readTVar (mGames mgr)
    running <- length . filter (== Nothing) <$> traverse (fmap gsResult . readTVar . lgState) (Map.elems games)
    if running >= maxRunning
      then pure (Left ("too many running games (at most " ++ show maxRunning ++ ")"))
      else do
        gid <- readTVar (mNextId mgr)
        writeTVar (mNextId mgr) (gid + 1)
        let lg = LiveGame gid ng initial chan
        writeTVar (mGames mgr) (Map.insert gid lg games)
        pure (Right lg)
  case result of
    Left err -> pure (Left err)
    Right lg -> do
      void (forkIO (runGame lg (mkGen (fromIntegral (lgId lg)))))
      pure (Right (lgId lg))

-- | The game loop: think, wait, publish, repeat until the game ends.
runGame :: LiveGame -> Gen -> IO ()
runGame lg = loop
  where
    ng = lgSetup lg
    loop g = do
      st <- readTVarIO (lgState lg)
      let p = gsPosition st
          plies = length (gsMoves st)
      case B.winner p of
        Just w -> finish (WonBy w)
        Nothing
          | plies >= ngPlyCap ng -> finish DrawByCap
          | otherwise -> do
              let bot = if B.bWhiteToMove p then ngWhite ng else ngBlack ng
                  mover = if B.bWhiteToMove p then White else Black
              case chooseMove bot g p of
                Nothing -> finish DrawByCap -- unreachable (R05)
                Just (m, g') -> do
                  -- Think in this thread, not inside the STM transaction.
                  _ <- evaluate m
                  threadDelay (ngDelayMs ng * 1000)
                  let p' = B.applyMove m p
                      ev = moveEventJson (plies + 1) mover m p'
                  atomically $ do
                    writeTVar (lgState lg) st {gsMoves = m : gsMoves st, gsPosition = p'}
                    writeTChan (lgEvents lg) (MoveEvent ev)
                  loop g'
    finish r = atomically $ do
      modifyTVar' (lgState lg) (\s -> s {gsResult = Just r})
      writeTChan (lgEvents lg) (EndEvent r)

lookupGame :: Manager -> Int -> IO (Maybe LiveGame)
lookupGame mgr gid = Map.lookup gid <$> readTVarIO (mGames mgr)

-- | All games, newest first, with their states.
listGames :: Manager -> IO [(LiveGame, GameState)]
listGames mgr = atomically $ do
  games <- readTVar (mGames mgr)
  traverse (\lg -> (,) lg <$> readTVar (lgState lg)) (reverse (Map.elems games))

-- | Subscribe to a game: its current state plus a channel of later events.
watch :: LiveGame -> IO (GameState, TChan Event)
watch lg = atomically $ (,) <$> readTVar (lgState lg) <*> dupTChan (lgEvents lg)

-- | The fields shared by a snapshot and a summary.
common :: LiveGame -> GameState -> [(Key, Value)]
common lg st =
  [ "id" .= T.pack (show (lgId lg))
  , "white" .= T.pack (renderSpec (ngWhite ng))
  , "black" .= T.pack (renderSpec (ngBlack ng))
  , "status" .= (if gsResult st == Nothing then "running" else "finished" :: T.Text)
  , "result" .= resultJson (gsResult st)
  , "plyCap" .= ngPlyCap ng
  , "delayMs" .= ngDelayMs ng
  ]
  where
    ng = lgSetup lg

-- | A game snapshot (docs/web-protocol.md).
snapshotJson :: LiveGame -> GameState -> Value
snapshotJson lg st =
  object $
    common lg st
      ++ [ "moves" .= map (T.pack . renderMove . B.toRefMove) (reverse (gsMoves st))
         , "position" .= positionJson (gsPosition st)
         ]

-- | A game summary (docs/web-protocol.md).
summaryJson :: LiveGame -> GameState -> Value
summaryJson lg st = object (common lg st ++ ["plies" .= length (gsMoves st)])
