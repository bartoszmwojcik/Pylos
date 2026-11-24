{-# LANGUAGE OverloadedStrings #-}

-- | Tests of human-vs-bot play on the server (E05-S02, #32; D18, ADR 0025).
--
-- Most tests drive the game manager ("Pylos.Server.Games") directly; a few
-- go through HTTP to check the routes and status codes.
module ServerTests (tests) where

import Control.Concurrent.STM
import Data.Aeson (Value (..))
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

tests :: TestTree
tests = testGroup "E05-S02 human-vs-bot play on the server (D18)" [managerTests, ruleTests, httpTests]

-- ---------------------------------------------------------------------------
-- The game manager

managerTests :: TestTree
managerTests =
  testGroup
    "game manager"
    [ testCase "a human game waits for the human, then the bot replies to a legal move" $ do
        lg <- start (NewGame Human (Bot RandomBot) 5000 300)
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
        lg <- start (NewGame (Bot RandomBot) Human 5000 300)
        st <- waitPlies lg 1
        waitingFor (lgSetup lg) st @?= Just Black
        humanSide (lgSetup lg) @?= Just Black
        move <- legalText st
        r <- submitMove lg move
        either (assertFailure . show) (const (pure ())) r
        _ <- waitPlies lg 3
        pure ()
    , testCase "negative: illegal and malformed moves leave the game unchanged" $ do
        lg <- start (NewGame Human (Bot RandomBot) 0 300)
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
        lg <- start (NewGame Human (Bot (MctsBot 5000)) 0 300)
        r1 <- submitMove lg "a11"
        r2 <- submitMove lg "a12"
        either (assertFailure . show) (const (pure ())) r1
        case r2 of
          Left (NotYourTurn Black) -> pure ()
          other -> assertFailure ("expected NotYourTurn Black, got " ++ show (fmap (const ()) other))
    , testCase "negative: a bot-vs-bot game refuses moves" $ do
        lg <- start (NewGame (Bot RandomBot) (Bot RandomBot) 1000 300)
        r <- submitMove lg "a11"
        case r of
          Left NoHuman -> pure ()
          _ -> assertFailure "a bot-vs-bot game accepted a move"
    , testCase "a full game ends with an end event, and records human as a player" $ do
        lg <- start (NewGame Human (Bot (GreedyBot defaultWeights)) 0 12)
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
        ids <- mapM (const (startGame mgr (NewGame Human (Bot RandomBot) 0 300))) [1 .. maxRunning + 2]
        all isRight ids @? "a waiting human game was counted as running"
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
        let ng = NewGame Human (Bot RandomBot) 0 300
            moves = ["a11", "a44", "a12", "a43", "a21", "a34"]
            st = foldl step start0 moves
            step s t = case checkHumanMoveAny s t of
              Right m -> GameState (m : gsMoves s) (B.applyMove m (gsPosition s)) Nothing
              Left err -> error err
        fmap (renderMove . B.toRefMove) (checkHumanMove ng st "a22 x a12 a11") @?= Right "a22 x a11 a12"
    , testCase "negative: out of turn names the side to move" $ do
        let ng = NewGame (Bot RandomBot) Human 0 300
        checkHumanMove ng start0 "a11" @?= Left (NotYourTurn White)
    , testCase "negative: a game at its ply cap is finished even before the thread ends it" $ do
        let ng = NewGame Human (Bot RandomBot) 0 0
        checkHumanMove ng start0 "a11" @?= Left GameFinished
    , testCase "players are parsed and rendered" $ do
        parsePlayer "human" @?= Right Human
        parsePlayer " human " @?= Right Human
        parsePlayer "random" @?= Right (Bot RandomBot)
        map renderPlayer [Human, Bot (AlphaBetaBot 3)] @?= ["human", "alphabeta:depth=3"]
    ]
  where
    start0 = GameState [] B.startPosition Nothing
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
    ]
  where
    testApp :: IO Application
    testApp = newManager >>= \m -> application m "web"
    postJson path body =
      srequest (SRequest (setPath defaultRequest {requestMethod = methodPost} path) body)

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
