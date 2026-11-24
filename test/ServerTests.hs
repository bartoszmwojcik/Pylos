{-# LANGUAGE OverloadedStrings #-}

-- | Tests of human-vs-bot play on the server (E05-S02, #32; D18, ADR 0025),
-- and of training games (E05-S05, #35; D22, ADR 0026).
--
-- Most tests drive the game manager ("Pylos.Server.Games") directly; a few
-- go through HTTP to check the routes and status codes.
module ServerTests (tests) where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM
import Control.Exception (ErrorCall (..), throwIO, try)
import Control.Monad (replicateM_, when)
import Data.Aeson (Value (..))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import Network.HTTP.Types (methodPost)
import Network.Wai (Application, requestMethod)
import Network.Wai.Test
import System.Timeout (timeout)
import Test.Tasty
import Test.Tasty.HUnit

import qualified Pylos.Bitboard as B
import Pylos.Bot
import Pylos.Match (GameResult (..))
import Pylos.Reference.Board (Colour (..))
import Pylos.Reference.Notation (renderMove)
import Pylos.Server.App (application)
import Pylos.Server.Games
import Pylos.Server.Json (scoreJson)

tests :: TestTree
tests =
  testGroup
    "E05 human-vs-bot play on the server"
    [ testGroup "E05-S02 human-vs-bot play (D18)" [managerTests, ruleTests, httpTests]
    , trainingTests
    ]

-- ---------------------------------------------------------------------------
-- The game manager

managerTests :: TestTree
managerTests =
  testGroup
    "game manager"
    [ testCase "a human game waits for the human, then the bot replies to a legal move" $ do
        lg <- start (NewGame Human (Bot RandomBot) 5000 300 False)
        st0 <- readTVarIO (lgState lg)
        waitingFor (lgSetup lg) st0 @?= Just White
        (_, chan) <- watch lg
        r <- submitMove lg "a11"
        case r of
          Left why -> assertFailure (show why)
          Right ev -> field "by" ev @?= Just (String "white")
        -- The bot replies at once: delayMs (5 s here) is not used in a
        -- human game, so this finishes well within the 2-second timeout.
        st <- waitPlies lg 2
        waitingFor (lgSetup lg) st @?= Just White
        evs <- mapM (const (atomically (readTChan chan))) [1 :: Int, 2]
        [field "by" v | MoveEvent v <- evs] @?= [Just (String "white"), Just (String "black")]
        map (renderMove . B.toRefMove) (reverse (gsMoves st)) !! 0 @?= "a11"
    , testCase "a bot that plays first moves at once, then waits for the human" $ do
        lg <- start (NewGame (Bot RandomBot) Human 5000 300 False)
        st <- waitPlies lg 1
        waitingFor (lgSetup lg) st @?= Just Black
        humanSide (lgSetup lg) @?= Just Black
        move <- legalText st
        r <- submitMove lg move
        either (assertFailure . show) (const (pure ())) r
        _ <- waitPlies lg 3
        pure ()
    , testCase "negative: illegal and malformed moves leave the game unchanged" $ do
        lg <- start (NewGame Human (Bot RandomBot) 0 300 False)
        st0 <- readTVarIO (lgState lg)
        r1 <- submitMove lg "b11" -- level 2 has no support yet (R03)
        r2 <- submitMove lg "zz9"
        r3 <- submitMove lg ""
        assertIllegal r1
        assertMalformed r2
        assertMalformed r3
        st1 <- readTVarIO (lgState lg)
        sameState st0 st1
    , testCase "negative: two moves posted at once: exactly one is accepted" $ do
        -- The bot is slow enough that it is still thinking when the second
        -- move arrives, so the second must be refused as out of turn.
        lg <- start (NewGame Human (Bot (MctsBot 5000)) 0 300 False)
        r1 <- submitMove lg "a11"
        r2 <- submitMove lg "a12"
        either (assertFailure . show) (const (pure ())) r1
        case r2 of
          Left (NotYourTurn Black) -> pure ()
          other -> assertFailure ("expected NotYourTurn Black, got " ++ show (fmap (const ()) other))
    , testCase "negative: a bot-vs-bot game refuses moves" $ do
        lg <- start (NewGame (Bot RandomBot) (Bot RandomBot) 1000 300 False)
        r <- submitMove lg "a11"
        case r of
          Left NoHuman -> pure ()
          _ -> assertFailure "a bot-vs-bot game accepted a move"
    , testCase "a full game ends with an end event, and records human as a player" $ do
        lg <- start (NewGame Human (Bot (GreedyBot defaultWeights)) 0 12 False)
        (_, chan) <- watch lg
        final <- playOut lg
        gsResult final @?= Just DrawByCap
        length (gsMoves final) @?= 12
        evs <- drain chan
        case reverse evs of
          (EndEvent DrawByCap : _) -> pure ()
          _ -> assertFailure "no end event"
        let snap = snapshotJson lg final
        field "white" snap @?= Just (String "human")
        field "black" snap @?= Just (String "greedy:reserve=10,free=1")
        field "human" snap @?= Just (String "white")
        field "waitingFor" snap @?= Just Null
        field "status" snap @?= Just (String "finished")
        r <- submitMove lg "a11"
        case r of
          Left GameFinished -> pure ()
          _ -> assertFailure "a finished game accepted a move"
    , testCase "a game waiting for the human does not count against the running limit" $ do
        mgr <- newManager
        ids <- mapM (const (startGame mgr (NewGame Human (Bot RandomBot) 0 300 False))) [1 .. maxRunning + 2]
        all isRight ids @? "a waiting human game was counted as running"
    , testCase "at most maxThinking bots think at once; the next one waits" $ do
        t <- newTVarIO 0
        release <- newEmptyTMVarIO
        -- Fill every place with a 'bot' that thinks until released.
        replicateM_ maxThinking $ forkIO (withThinkingPlace t (atomically (readTMVar release)))
        atomically (readTVar t >>= \n -> when (n < maxThinking) retry)
        extra <- timeout 200000 (withThinkingPlace t (pure ()))
        extra @?= Nothing
        atomically (putTMVar release ())
        later <- timeout 5000000 (withThinkingPlace t (pure ()))
        later @?= Just ()
    , testCase "a bot that throws gives its thinking place back" $ do
        t <- newTVarIO 0
        r <- try (withThinkingPlace t (throwIO (ErrorCall "boom"))) :: IO (Either ErrorCall ())
        r @?= Left (ErrorCall "boom")
        readTVarIO t >>= (@?= 0)
    ]
  where
    isRight = either (const False) (const True)

-- ---------------------------------------------------------------------------
-- The pure acceptance rules

ruleTests :: TestTree
ruleTests =
  testGroup
    "checkHumanMove"
    [ testCase "take-backs may be written in any order" $ do
        -- Build a position where White completes a square a11 a12 a21 a22
        -- (level 1) and may take back two balls.
        let ng = NewGame Human (Bot RandomBot) 0 300 False
            moves = ["a11", "a44", "a12", "a43", "a21", "a34"]
            st = foldl step start0 moves
            step s t = case checkHumanMoveAny s t of
              Right m -> GameState (m : gsMoves s) (B.applyMove m (gsPosition s)) Nothing Nothing
              Left err -> error err
        fmap (renderMove . B.toRefMove) (checkHumanMove ng st "a22 x a12 a11") @?= Right "a22 x a11 a12"
    , testCase "negative: out of turn names the side to move" $ do
        let ng = NewGame (Bot RandomBot) Human 0 300 False
        checkHumanMove ng start0 "a11" @?= Left (NotYourTurn White)
    , testCase "negative: a game at its ply cap is finished even before the thread ends it" $ do
        let ng = NewGame Human (Bot RandomBot) 0 0 False
        checkHumanMove ng start0 "a11" @?= Left GameFinished
    , testCase "players are parsed and rendered" $ do
        parsePlayer "human" @?= Right Human
        parsePlayer " human " @?= Right Human
        parsePlayer "random" @?= Right (Bot RandomBot)
        map renderPlayer [Human, Bot (AlphaBetaBot 3)] @?= ["human", "alphabeta:depth=3"]
    ]
  where
    start0 = GameState [] B.startPosition Nothing Nothing
    -- Look a move up among the legal moves, whoever is to move.
    checkHumanMoveAny s t =
      case [m | m <- B.legalMoves (gsPosition s), renderMove (B.toRefMove m) == t] of
        (m : _) -> Right m
        [] -> Left ("not legal in test setup: " ++ t)

-- ---------------------------------------------------------------------------
-- HTTP

httpTests :: TestTree
httpTests =
  testGroup
    "HTTP"
    [ testCase "POST /api/games/:id/move plays the move and answers its event" $ do
        app <- testApp
        flip runSession app $ do
          r <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"random\"}"
          assertStatus 201 r
          g <- request (setPath defaultRequest "/api/games/1")
          assertBodyContains "\"waitingFor\":\"white\"" g
          assertBodyContains "\"human\":\"white\"" g
          m <- postJson "/api/games/1/move" "{\"move\":\"a11\"}"
          assertStatus 200 m
          assertBodyContains "\"ply\":1" m
          assertBodyContains "\"by\":\"white\"" m
    , testCase "negative: bad moves are 400 with a message, unknown games 404" $ do
        app <- testApp
        flip runSession app $ do
          _ <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"random\"}"
          bad1 <- postJson "/api/games/1/move" "{\"move\":\"b11\"}"
          assertStatus 400 bad1
          assertBodyContains "illegal move" bad1
          bad2 <- postJson "/api/games/1/move" "{\"move\":\"q1\"}"
          assertStatus 400 bad2
          assertBodyContains "not a move" bad2
          bad3 <- postJson "/api/games/1/move" "not json"
          assertStatus 400 bad3
          missing <- postJson "/api/games/42/move" "{\"move\":\"a11\"}"
          assertStatus 404 missing
          g <- request (setPath defaultRequest "/api/games/1")
          assertBodyContains "\"moves\":[]" g
    , testCase "negative: two humans are a 400" $ do
        app <- testApp
        flip runSession app $ do
          r <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"human\"}"
          assertStatus 400 r
          assertBodyContains "human" r
          r2 <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"chess\"}"
          assertStatus 400 r2
          assertBodyContains "chess" r2
    , testCase "browser files must be revalidated (no stale app.js after an upgrade)" $ do
        app <- testApp
        flip runSession app $ do
          page <- request (setPath defaultRequest "/")
          assertStatus 200 page
          assertHeader "Cache-Control" "no-cache" page
          js <- request (setPath defaultRequest "/static/app.js")
          assertStatus 200 js
          assertHeader "Cache-Control" "no-cache" js
    ]
  where
    testApp :: IO Application
    testApp = newManager >>= \m -> application m "web"

postJson :: BS.ByteString -> BL.ByteString -> Session SResponse
postJson path body =
  srequest (SRequest (setPath defaultRequest {requestMethod = methodPost} path) body)

-- ---------------------------------------------------------------------------
-- Training games (E05-S05, D22)

trainingTests :: TestTree
trainingTests =
  testGroup
    "E05-S05 training games (D22)"
    [ testCase "same seed: the bot plays the same moves in a training and a real game" $
        -- A fresh manager numbers its first game 1, and the game id is the
        -- seed, so both games use the same random numbers. The scripted
        -- human always plays the first legal move.
        mapM_ sameGame [GreedyBot defaultWeights, MctsBot 100, AlphaBetaBot 2, RandomBot]
    , testCase "greedy: every ply is scored with the shared evaluation" $ do
        let bot = GreedyBot defaultWeights
        (final, evs) <- played (NewGame Human (Bot bot) 0 10 True)
        let scores = scoreEvents evs
        map fst scores @?= [1 .. 10]
        -- After each ply, human's or bot's, the score is greedy's
        -- evaluation of the position after that ply.
        let positions = scanl (flip B.applyMove) B.startPosition (reverse (gsMoves final))
        map snd scores @?= map (scoreJson . scorePosition bot) (drop 1 positions)
    , testCase "alpha-beta: the human's ply gets the score of the bot's one search" $ do
        (_, evs) <- played (NewGame Human (Bot (AlphaBetaBot 2)) 0 8 True)
        let scores = scoreEvents evs
        map fst scores @?= [1 .. 8]
        -- The position after the human's move and the one after the bot's
        -- reply get the same value: the root value of the bot's search.
        let pairs = [(a, b) | ((p, a), (_, b)) <- zip scores (drop 1 scores), odd p]
        length pairs @?= 4
        all (uncurry (==)) pairs @? ("scores differ: " ++ show scores)
        all (isKind "eval" . snd) scores @? "not an eval score"
    , testCase "mcts: a win rate after its own moves, none after the human's" $ do
        (_, evs) <- played (NewGame Human (Bot (MctsBot 100)) 0 6 True)
        let scores = scoreEvents evs
        map fst scores @?= [1 .. 6]
        all (isKind "none" . snd) [s | s@(p, _) <- scores, odd p] @? show scores
        all (isKind "winRate" . snd) [s | s@(p, _) <- scores, even p] @? show scores
    , testCase "random, playing first: every ply has the none score" $ do
        (_, evs) <- played (NewGame (Bot RandomBot) Human 0 5 True)
        let scores = scoreEvents evs
        map fst scores @?= [1 .. 5]
        all (isKind "none" . snd) scores @? show scores
    , testCase "each score event follows the move it scores" $ do
        (_, evs) <- played (NewGame Human (Bot (AlphaBetaBot 2)) 0 4 True)
        map tag evs @?= ["move 1", "score 1", "move 2", "score 2", "move 3", "score 3", "move 4", "score 4", "end"]
    , testCase "the snapshot has the training flag and the newest score" $ do
        (lg, final) <- playedGame (NewGame Human (Bot (GreedyBot defaultWeights)) 0 4 True)
        let snap = snapshotJson lg final
        field "training" snap @?= Just (Bool True)
        (field "score" snap >>= field "ply") @?= Just (Number 4)
        (field "score" snap >>= field "score" >>= field "kind") @?= Just (String "eval")
        field "training" (summaryJson lg final) @?= Just (Bool True)
    , testCase "negative: a real game sends no score and its snapshot has none" $ do
        (lg, final, evs) <- playedWithEvents (NewGame Human (Bot (AlphaBetaBot 2)) 0 6 False)
        scoreEvents evs @?= []
        length [() | MoveEvent _ <- evs] @?= 6
        let snap = snapshotJson lg final
        field "training" snap @?= Just (Bool False)
        field "score" snap @?= Just Null
    , testCase "scores are shown as eval (decided at winScore), winRate or none" $ do
        scoreJson (EvalScore 37) @?= obj [("kind", String "eval"), ("value", Number 37), ("decided", Bool False)]
        field "decided" (scoreJson (EvalScore (negate winScore))) @?= Just (Bool True)
        field "decided" (scoreJson (EvalScore (winScore - 1))) @?= Just (Bool False)
        scoreJson (WinRate 0.5) @?= obj [("kind", String "winRate"), ("value", Number 0.5)]
        scoreJson NoScore @?= obj [("kind", String "none")]
    , testCase "HTTP: a training game is created with training:true; without a human it is a 400" $ do
        app <- newManager >>= \m -> application m "web"
        flip runSession app $ do
          r <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"greedy\",\"training\":true}"
          assertStatus 201 r
          g <- request (setPath defaultRequest "/api/games/1")
          assertBodyContains "\"training\":true" g
          assertBodyContains "\"score\":null" g
          real <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"greedy\"}"
          assertStatus 201 real
          g2 <- request (setPath defaultRequest "/api/games/2")
          assertBodyContains "\"training\":false" g2
          bad <- postJson "/api/games" "{\"white\":\"random\",\"black\":\"greedy\",\"training\":true}"
          assertStatus 400 bad
          assertBodyContains "training needs a human" bad
          bad2 <- postJson "/api/games" "{\"white\":\"human\",\"black\":\"greedy\",\"training\":\"yes\"}"
          assertStatus 400 bad2
    ]
  where
    sameGame bot = do
      (_, real) <- playedGame (NewGame Human (Bot bot) 0 30 False)
      (_, training) <- playedGame (NewGame Human (Bot bot) 0 30 True)
      assertEqual ("moves of " ++ renderSpec bot) (reverse (gsMoves real)) (reverse (gsMoves training))
    played ng = (\(_, st, evs) -> (st, evs)) <$> playedWithEvents ng
    playedGame ng = (\(lg, st, _) -> (lg, st)) <$> playedWithEvents ng
    playedWithEvents ng = do
      lg <- start ng
      (_, chan) <- watch lg
      final <- playOut lg
      evs <- drain chan
      pure (lg, final, evs)
    scoreEvents :: [Event] -> [(Int, Value)]
    scoreEvents evs = [(truncate p, s) | ScoreEvent v <- evs, Just (Number p) <- [field "ply" v], Just s <- [field "score" v]]
    isKind k s = field "kind" s == Just (String k)
    tag (MoveEvent v) = "move " ++ plyOf v
    tag (ScoreEvent v) = "score " ++ plyOf v
    tag (EndEvent _) = "end"
    plyOf v = case field "ply" v of
      Just (Number p) -> show (truncate p :: Int)
      _ -> "?"
    obj kvs = Object (KM.fromList [(Key.fromString k, v) | (k, v) <- kvs])

-- ---------------------------------------------------------------------------
-- Helpers

-- | Start a game on a fresh manager.
start :: NewGame -> IO LiveGame
start ng = do
  mgr <- newManager
  r <- startGame mgr ng
  case r of
    Left err -> assertFailure err >> error "unreachable"
    Right gid -> lookupGame mgr gid >>= maybe (assertFailure "lost game" >> error "unreachable") pure

-- | Wait (at most 10 s) until the game has at least this many moves, or has
-- finished.
waitPlies :: LiveGame -> Int -> IO GameState
waitPlies lg n = do
  r <- timeout 10000000 $ atomically $ do
    st <- readTVar (lgState lg)
    check (length (gsMoves st) >= n || gsResult st /= Nothing)
    pure st
  maybe (assertFailure ("timed out waiting for ply " ++ show n) >> error "unreachable") pure r

-- | Wait until the game waits for the human or has finished.
waitTurnOrEnd :: LiveGame -> IO GameState
waitTurnOrEnd lg = do
  r <- timeout 10000000 $ atomically $ do
    st <- readTVar (lgState lg)
    check (waitingFor (lgSetup lg) st /= Nothing || gsResult st /= Nothing)
    pure st
  maybe (assertFailure "timed out waiting for the human's turn" >> error "unreachable") pure r

-- | Play the first legal move every turn until the game ends.
playOut :: LiveGame -> IO GameState
playOut lg = do
  st <- waitTurnOrEnd lg
  case gsResult st of
    Just _ -> pure st
    Nothing -> do
      move <- legalText st
      r <- submitMove lg move
      either (assertFailure . show) (const (pure ())) r
      playOut lg

-- | A legal move in the state's position, as text.
legalText :: GameState -> IO String
legalText st = case B.legalMoves (gsPosition st) of
  (m : _) -> pure (renderMove (B.toRefMove m))
  [] -> assertFailure "no legal move" >> error "unreachable"

-- | Every event already in the channel.
drain :: TChan Event -> IO [Event]
drain chan = atomically go
  where
    go = do
      ev <- tryReadTChan chan
      case ev of
        Nothing -> pure []
        Just e -> (e :) <$> go

field :: String -> Value -> Maybe Value
field k (Object o) = KM.lookup (Key.fromString k) o
field _ _ = Nothing

sameState :: GameState -> GameState -> Assertion
sameState a b = do
  gsMoves a @?= gsMoves b
  gsPosition a @?= gsPosition b
  gsResult a @?= gsResult b

assertIllegal :: Either MoveRejected a -> Assertion
assertIllegal (Left (Illegal _)) = pure ()
assertIllegal (Left other) = assertFailure ("expected Illegal, got " ++ show other)
assertIllegal (Right _) = assertFailure "an illegal move was accepted"

assertMalformed :: Either MoveRejected a -> Assertion
assertMalformed (Left (Malformed err)) = not (null err) @? "empty message"
assertMalformed (Left other) = assertFailure ("expected Malformed, got " ++ show other)
assertMalformed (Right _) = assertFailure "a malformed move was accepted"
