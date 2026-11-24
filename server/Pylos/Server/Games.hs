{-# LANGUAGE OverloadedStrings #-}

-- | Live games (S4, S5): each game runs in its own thread and broadcasts
-- its moves to every browser watching it. One side may be a human (D18).
--
-- The shared state lives in STM variables ('TVar'). A watcher takes the
-- current snapshot and subscribes to the event channel in /one/ atomic
-- step, so it can never miss a move or see one twice.
--
-- __Who changes a game.__ Exactly one party may move at any moment: the
-- side to move. When that side is a bot, only the game thread writes; when
-- it is the human, only 'submitMove' can. 'submitMove' checks the turn,
-- the legality and the state /and/ applies the move in one STM transaction,
-- so two moves posted at the same time cannot both be accepted: the second
-- transaction sees that it is no longer the human's turn. The game thread
-- meanwhile waits inside STM ('retry') until the turn passes to the bot.
-- See @docs/adr/0025-human-play-protocol.md@.
--
-- __Training games__ (D22). In a training game the bot also says how it
-- scores the position after every move, its own and the human's, as
-- @score@ events. A real game sends none, and its bot only calls
-- 'chooseMove'. The bot plays the same moves in both. See the Server
-- section of @docs/adr/0026-bot-scores.md@.
module Pylos.Server.Games
  ( Manager
  , newManager
  , Player (..)
  , parsePlayer
  , renderPlayer
  , NewGame (..)
  , humanSide
  , startGame
  , LiveGame (..)
  , GameState (..)
  , Event (..)
  , lookupGame
  , listGames
  , watch
  , waitingFor
  , MoveRejected (..)
  , rejectionText
  , checkHumanMove
  , submitMove
  , snapshotJson
  , summaryJson
  , maxRunning
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM
import Control.Exception (evaluate)
import Control.Monad (void, when)
import Data.Aeson
import Data.Foldable (traverse_)
import Data.List (find)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import qualified Pylos.Bitboard as B
import Pylos.Bot
import Pylos.Match (GameResult (..))
import Pylos.Reference.Board (Colour (..))
import Pylos.Reference.Notation (parseMove, renderMove)
import Pylos.Reference.Random (Gen, mkGen)
import Pylos.Server.Json

-- | Who plays one side: a bot, or the human at the browser (D18).
data Player
  = Bot BotSpec
  | Human
  deriving (Eq, Show)

-- | Read a player: @human@, or a bot spec (D15).
parsePlayer :: String -> Either String Player
parsePlayer s
  | words s == ["human"] = Right Human
  | otherwise = Bot <$> parseSpec s

-- | Write a player as 'parsePlayer' reads it. This is also what the
-- snapshot shows as @white@ / @black@.
renderPlayer :: Player -> String
renderPlayer Human = "human"
renderPlayer (Bot spec) = renderSpec spec

-- | A request for a new game, already validated: at most one side is
-- 'Human' (D18).
data NewGame = NewGame
  { ngWhite :: Player
  , ngBlack :: Player
  , ngDelayMs :: Int
  -- ^ the pause before each bot move, only in bot-vs-bot games
  , ngPlyCap :: Int
  , ngTraining :: Bool
  -- ^ a training game (D22): the bot's scores are sent. Only with a human
  -- player; fixed for the whole game.
  }

-- | The colour the human plays, if any.
humanSide :: NewGame -> Maybe Colour
humanSide ng
  | ngWhite ng == Human = Just White
  | ngBlack ng == Human = Just Black
  | otherwise = Nothing

-- | Who plays a colour.
playerOf :: NewGame -> Colour -> Player
playerOf ng White = ngWhite ng
playerOf ng Black = ngBlack ng

-- | What changes while a game runs.
data GameState = GameState
  { gsMoves :: [B.BMove]
  -- ^ newest first
  , gsPosition :: B.BPosition
  , gsResult :: Maybe GameResult
  , gsScore :: Maybe (Int, BotScore)
  -- ^ the newest score of a training game, with the ply it scores (the
  -- position after that many moves). Always 'Nothing' in a real game.
  }

-- | What a watcher is told.
data Event
  = MoveEvent Value
  | ScoreEvent Value
  -- ^ training games only (D22)
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

-- | At most this many games use the processor at once, so the server stays
-- responsive. A game that is waiting for the human does not count: it uses
-- no processor time, and an abandoned human game would otherwise hold a
-- place for ever.
maxRunning :: Int
maxRunning = 8

-- | Whose colour is to move in a position.
sideToMove :: B.BPosition -> Colour
sideToMove p = if B.bWhiteToMove p then White else Black

-- | Is the game over? A win (R05) or the ply cap (D12).
gameOver :: NewGame -> GameState -> Maybe GameResult
gameOver ng st = case B.winner (gsPosition st) of
  Just w -> Just (WonBy w)
  Nothing
    | length (gsMoves st) >= ngPlyCap ng -> Just DrawByCap
    | otherwise -> Nothing

-- | The human's colour when the game is waiting for the human's move:
-- the game is not finished and the human is to move. 'Nothing' otherwise,
-- including while the bot thinks and in a bot-vs-bot game.
waitingFor :: NewGame -> GameState -> Maybe Colour
waitingFor ng st
  | gsResult st /= Nothing = Nothing
  | gameOver ng st /= Nothing = Nothing -- the game thread is about to end it
  | playerOf ng mover == Human = Just mover
  | otherwise = Nothing
  where
    mover = sideToMove (gsPosition st)

-- | Start a game in a new thread. Fails when too many games are running.
startGame :: Manager -> NewGame -> IO (Either String Int)
startGame mgr ng = do
  initial <- newTVarIO (GameState [] B.startPosition Nothing Nothing)
  chan <- newBroadcastTChanIO
  result <- atomically $ do
    games <- readTVar (mGames mgr)
    states <- traverse (\lg -> (,) lg <$> readTVar (lgState lg)) (Map.elems games)
    let busy (lg, st) = gsResult st == Nothing && waitingFor (lgSetup lg) st == Nothing
        running = length (filter busy states)
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

-- | The game loop. Until the game ends: wait for the bot's turn, think,
-- (in a bot-vs-bot game) wait 'ngDelayMs', publish.
runGame :: LiveGame -> Gen -> IO ()
runGame lg = loop
  where
    ng = lgSetup lg
    loop g = do
      -- Block (without using the processor) while the human is to move.
      -- 'retry' wakes up again as soon as 'submitMove' writes the state.
      st <- atomically $ do
        s <- readTVar (lgState lg)
        when (waitingFor ng s /= Nothing) retry
        pure s
      case gameOver ng st of
        Just r -> finish r
        Nothing -> do
          let p = gsPosition st
              mover = sideToMove p
          case playerOf ng mover of
            Human -> loop g -- unreachable: 'waitingFor' returned Nothing
            Bot bot -> do
              let ply = length (gsMoves st)
                  -- In a training game, the bot scores the position the
                  -- human's move led to. Sides alternate, so a move before
                  -- the bot's turn is the human's.
                  scoreHuman = ngTraining ng && ply > 0
                  -- Alpha-beta's score of that position is the root value
                  -- of the search it is about to run, so it comes with the
                  -- move below: one search, not two. The other bots score
                  -- it at once: a cheap evaluation, or no score at all.
                  early = scoreHuman && not (isAlphaBeta bot)
              when early $ do
                s <- evaluate (scorePosition bot p)
                atomically (publishScore lg ply s)
              case think bot g p of
                Nothing -> finish DrawByCap -- unreachable (R05)
                Just (m, g', score) -> do
                  -- Think in this thread, not inside the STM transaction.
                  _ <- evaluate m
                  _ <- traverse evaluate score
                  -- In a human game the bot answers at once (ADR 0025).
                  when (humanSide ng == Nothing) $ threadDelay (ngDelayMs ng * 1000)
                  -- It is the bot's turn, so nobody else can have changed
                  -- the state since we read it. The human's score, the
                  -- move and the bot's score go out in one transaction.
                  atomically $ do
                    when (scoreHuman && not early) $ traverse_ (publishScore lg ply) score
                    void (publish lg m)
                    traverse_ (publishScore lg (ply + 1)) score
                  loop g'
    -- A real game asks only for the move (D22). 'chooseMove' is
    -- 'chooseMoveScored' with the score dropped, so the move and the
    -- generator are the same in both kinds of game (ADR 0026).
    think bot g p
      | ngTraining ng = (\(m, g', s) -> (m, g', Just s)) <$> chooseMoveScored bot g p
      | otherwise = (\(m, g') -> (m, g', Nothing)) <$> chooseMove bot g p
    isAlphaBeta (AlphaBetaBot _) = True
    isAlphaBeta _ = False
    finish r = atomically $ do
      modifyTVar' (lgState lg) (\s -> s {gsResult = Just r})
      writeTChan (lgEvents lg) (EndEvent r)

-- | Apply a move to a game and tell the watchers, in one transaction.
-- Returns the data of the @move@ event.
publish :: LiveGame -> B.BMove -> STM Value
publish lg m = do
  st <- readTVar (lgState lg)
  let p = gsPosition st
      p' = B.applyMove m p
      ev = moveEventJson (length (gsMoves st) + 1) (sideToMove p) m p'
  writeTVar (lgState lg) st {gsMoves = m : gsMoves st, gsPosition = p'}
  writeTChan (lgEvents lg) (MoveEvent ev)
  pure ev

-- | Record and broadcast the bot's score of the position after @ply@
-- moves (training games only).
publishScore :: LiveGame -> Int -> BotScore -> STM ()
publishScore lg ply s = do
  modifyTVar' (lgState lg) (\st -> st {gsScore = Just (ply, s)})
  writeTChan (lgEvents lg) (ScoreEvent (plyScoreJson ply s))

-- | Why a posted move was refused. The game is unchanged in every case.
data MoveRejected
  = NoHuman
  -- ^ both sides are bots
  | GameFinished
  | NotYourTurn Colour
  -- ^ the colour that is to move (the bot's)
  | Malformed String
  -- ^ the text is not a move in D09 notation; the parser's message
  | Illegal String
  -- ^ a well-formed move that is not legal here (R03–R08)
  deriving (Eq, Show)

-- | The message sent to the browser.
rejectionText :: MoveRejected -> String
rejectionText NoHuman = "this game has no human player"
rejectionText GameFinished = "the game is over"
rejectionText (NotYourTurn c) = "it is not your turn: " ++ T.unpack (colourText c) ++ " (the bot) is to move"
rejectionText (Malformed err) = "not a move: " ++ err
rejectionText (Illegal mv) = "illegal move: \"" ++ mv ++ "\""

-- | Check a move the human posted, as text in D09 notation. Pure, so the
-- rules of acceptance are easy to test.
--
-- The text is read with the reference parser, then looked up among the
-- bitboard engine's legal moves (R03–R08). Comparing whole moves means the
-- take-backs may be written in any order (@x a12 a11@ is @x a11 a12@).
checkHumanMove :: NewGame -> GameState -> String -> Either MoveRejected B.BMove
checkHumanMove ng st text = do
  when (humanSide ng == Nothing) (Left NoHuman)
  when (gsResult st /= Nothing || gameOver ng st /= Nothing) (Left GameFinished)
  let p = gsPosition st
  when (waitingFor ng st == Nothing) (Left (NotYourTurn (sideToMove p)))
  wanted <- either (Left . Malformed) Right (parseMove text)
  case find (\m -> B.toRefMove m == wanted) (B.legalMoves p) of
    Nothing -> Left (Illegal (renderMove wanted))
    Just m -> Right m

-- | Play the human's move: check it and apply it in one STM transaction
-- (race-free, see the module header). On success the @move@ event is
-- broadcast and its data returned; the bot's reply follows on the event
-- stream.
submitMove :: LiveGame -> String -> IO (Either MoveRejected Value)
submitMove lg text = atomically $ do
  st <- readTVar (lgState lg)
  case checkHumanMove (lgSetup lg) st text of
    Left why -> pure (Left why)
    Right m -> Right <$> publish lg m

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
  , "white" .= T.pack (renderPlayer (ngWhite ng))
  , "black" .= T.pack (renderPlayer (ngBlack ng))
  , "human" .= fmap colourText (humanSide ng)
  , "waitingFor" .= fmap colourText (waitingFor ng st)
  , "status" .= (if gsResult st == Nothing then "running" else "finished" :: T.Text)
  , "result" .= resultJson (gsResult st)
  , "plyCap" .= ngPlyCap ng
  , "delayMs" .= ngDelayMs ng
  , "training" .= ngTraining ng
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
         , "score" .= fmap (uncurry plyScoreJson) (gsScore st)
         ]

-- | A game summary (docs/web-protocol.md).
summaryJson :: LiveGame -> GameState -> Value
summaryJson lg st = object (common lg st ++ ["plies" .= length (gsMoves st)])
