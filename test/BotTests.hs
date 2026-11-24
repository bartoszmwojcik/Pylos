{-# LANGUAGE OverloadedStrings #-}

-- | Tests of the bots, the match runner and the live-game server (E04).
module BotTests (tests) where

import Control.Concurrent.STM
import Control.Monad.IO.Class (liftIO)
import Data.Aeson (Value (..), decode)
import Data.List (isInfixOf)
import Data.Word (Word64)
import Network.HTTP.Types (methodPost)
import Network.Wai (Application, requestMethod)
import Network.Wai.Test
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck

import Gen
import qualified Pylos.Bitboard as B
import Pylos.Bot
import Pylos.Match
import Pylos.Reference.Board
import Pylos.Reference.Move
import Pylos.Reference.Random (mkGen)
import Pylos.Reference.Record (decodeRecord, encodeRecord, replay)
import Pylos.Reference.Rules
import Pylos.Server.App (application)
import Pylos.Server.Games

tests :: TestTree
tests = testGroup "Bots, match runner and server" [botTests, matchTests, serverTests]

-- | Cheap settings of every bot kind, so the properties run quickly.
cheapBots :: [BotSpec]
cheapBots = [RandomBot, GreedyBot defaultWeights, AlphaBetaBot 2, MctsBot 30]

-- ---------------------------------------------------------------------------
-- E04-S01 (#18)

botTests :: TestTree
botTests =
  testGroup
    "E04-S01 bots (D15)"
    [ testProperty "every bot plays a move the reference engine calls legal" $
        \(Reachable _ p) (seed :: Word64) ->
          not (isGameOver p) ==>
            conjoin
              [ counterexample (renderSpec bot) $ case chooseMove bot (mkGen seed) (B.fromReference p) of
                  Nothing -> property False
                  Just (m, _) -> property (isLegal (B.toRefMove m) p)
              | bot <- cheapBots
              ]
    , testProperty "a bot asked twice with the same seed plays the same move" $
        \(Reachable _ p) (seed :: Word64) ->
          conjoin
            [ fmap fst (chooseMove bot (mkGen seed) bp) === fmap fst (chooseMove bot (mkGen seed) bp)
            | bot <- cheapBots
            , let bp = B.fromReference p
            ]
    , testCase "alpha-beta keeps its last ball instead of losing (R03, R05)" $ do
        -- White has one ball left. Placing it loses two plies later (R05);
        -- raising a33 onto b11 keeps it.
        let p = (mkPosition ["a11", "a21", "a33"] ["a12", "a22"] White) {whiteReserve = 1}
        forM' [2, 3] $ \d -> case chooseMove (AlphaBetaBot d) (mkGen 1) (B.fromReference p) of
          Nothing -> assertFailure "no move"
          Just (m, _) -> isRaise (B.toRefMove m) @? ("depth " ++ show d ++ " played " ++ show (B.toRefMove m))
    , testCase "specs are parsed, with defaults, and rendered back" $ do
        parseSpec "alphabeta:depth=4" @?= Right (AlphaBetaBot 4)
        parseSpec "alphabeta:depth=8" @?= Right (AlphaBetaBot 8)
        parseSpec "mcts" @?= Right (MctsBot 2000)
        parseSpec "greedy:free=3" @?= Right (GreedyBot (Weights 10 3))
        parseSpec " random " @?= Right RandomBot
        mapM_ (\b -> parseSpec (renderSpec b) @?= Right b) cheapBots
    , testCase "negative: bad specs are errors naming the bad part" $ do
        errNames "depth" (parseSpec "alphabeta:depth=0")
        errNames "depth" (parseSpec "alphabeta:depth=9")
        errNames "foo" (parseSpec "mcts:foo=1")
        errNames "chess" (parseSpec "chess")
        errNames "depth=x" (parseSpec "alphabeta:depth=x")
    ]
  where
    forM' xs f = mapM_ f (xs :: [Int])
    errNames part r = case r of
      Left err -> (part `isInfixOf` err) @? err
      Right b -> assertFailure ("parsed as " ++ show b)

-- ---------------------------------------------------------------------------
-- E04-S02 (#19)

matchTests :: TestTree
matchTests =
  testGroup
    "E04-S02 match runner (D12)"
    [ testProperty "a game never exceeds the cap, and a capped game is a draw" $
        \(seed :: Word64) (Small c) ->
          let cap = 1 + c `mod` 120
              g = playGame RandomBot RandomBot cap (mkGen seed)
           in property (length (gameMoves g) <= cap)
                .&&. (gameResult g /= DrawByCap || length (gameMoves g) == cap)
    , testProperty "a game record replays without error" $
        \(seed :: Word64) ->
          let g = playGame (GreedyBot defaultWeights) RandomBot 300 (mkGen seed)
              rec = gameRecord (GreedyBot defaultWeights) RandomBot g
           in case decodeRecord (encodeRecord rec) >>= replay of
                Left err -> counterexample err False
                Right _ -> property True
    , testCase "match totals add up and score both sides" $ do
        let results = [gameResult (playGame (GreedyBot defaultWeights) RandomBot 300 (mkGen s)) | s <- [1 .. 6]]
            a = foldMap (scoreGame White) results
            b = foldMap (scoreGame Black) results
        wins a + losses a + draws a @?= 6
        (wins a, losses a, draws a) @?= (losses b, wins b, draws b)
    ]

-- ---------------------------------------------------------------------------
-- E04-S03 (#20)

serverTests :: TestTree
serverTests =
  testGroup
    "E04-S03 server (D16)"
    [ testCase "a game's events extend its snapshot to the final position" $ do
        mgr <- newManager
        Right gid <- startGame mgr (NewGame RandomBot RandomBot 0 300)
        Just lg <- lookupGame mgr gid
        (st0, chan) <- watch lg
        events <- collectEvents chan
        final <- readTVarIO (lgState lg)
        let moveEvents = [() | MoveEvent _ <- events]
        length (gsMoves st0) + length moveEvents @?= length (gsMoves final)
        case reverse events of
          (EndEvent r : _) -> Just r @?= gsResult final
          _ -> assertFailure "no end event"
    , testCase "POST /api/games starts a game that GET can read" $ do
        app <- testApp
        flip runSession app $ do
          r <- postJson "/api/games" "{\"white\":\"random\",\"black\":\"greedy\",\"delayMs\":0}"
          assertStatus 201 r
          assertBodyContains "\"id\":\"1\"" r
          g <- request (setPath defaultRequest "/api/games/1")
          assertStatus 200 g
          assertBodyContains "\"white\":\"random\"" g
          l <- request (setPath defaultRequest "/api/games")
          assertBodyContains "\"plies\"" l
    , testCase "negative: a bad bot spec is a 400 naming it" $ do
        app <- testApp
        flip runSession app $ do
          r <- postJson "/api/games" "{\"white\":\"chess\",\"black\":\"random\"}"
          assertStatus 400 r
          assertBodyContains "chess" r
    , testCase "negative: unknown games and files are 404, and paths cannot escape web/" $ do
        app <- testApp
        flip runSession app $ do
          assertStatus 404 =<< request (setPath defaultRequest "/api/games/42")
          assertStatus 404 =<< request (setPath defaultRequest "/static/../pylos.cabal")
          assertStatus 404 =<< request (setPath defaultRequest "/static/%2e%2e/pylos.cabal")
          assertStatus 404 =<< request (setPath defaultRequest "/static/missing.js")
    , testCase "GET /api/bots lists the four kinds" $ do
        app <- testApp
        flip runSession app $ do
          r <- request (setPath defaultRequest "/api/bots")
          assertStatus 200 r
          case decode (simpleBody r) of
            Just (Array xs) -> liftIO (length xs @?= 4)
            _ -> liftIO (assertFailure "not a JSON array")
    ]
  where
    testApp :: IO Application
    testApp = newManager >>= \m -> application m "web"
    postJson path body =
      srequest (SRequest (setPath defaultRequest {requestMethod = methodPost} path) body)
    collectEvents chan = do
      ev <- atomically (readTChan chan)
      case ev of
        EndEvent _ -> pure [ev]
        _ -> (ev :) <$> collectEvents chan
