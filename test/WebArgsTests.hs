-- | E05-S01 (#31): the @pylos-web@ argument parser.
module WebArgsTests (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import WebArgs

tests :: TestTree
tests =
  testGroup
    "E05-S01 pylos-web arguments"
    [ testCase "no arguments: loopback, port 8080, web" $
        parseArgs [] @?= Right (Options 8080 "web" LoopbackOnly)
    , testCase "positional PORT and WEB_DIR still work" $ do
        parseArgs ["9000"] @?= Right (Options 9000 "web" LoopbackOnly)
        parseArgs ["9000", "static"] @?= Right (Options 9000 "static" LoopbackOnly)
    , testCase "--lan alone switches to the home network" $
        parseArgs ["--lan"] @?= Right (Options 8080 "web" HomeNetwork)
    , testCase "--lan may come before, between or after the positionals" $ do
        let want = Right (Options 9000 "static" HomeNetwork)
        parseArgs ["--lan", "9000", "static"] @?= want
        parseArgs ["9000", "--lan", "static"] @?= want
        parseArgs ["9000", "static", "--lan"] @?= want
    , testCase "an unparsable port falls back to 8080 as before" $
        parseArgs ["abc"] @?= Right (Options 8080 "web" LoopbackOnly)
    , testCase "an unknown option is rejected" $
        parseArgs ["--wan"] @?= Left "unknown option --wan"
    , testCase "too many positionals are rejected" $
        parseArgs ["1", "d", "x"] @?= Left "too many arguments"
    , testCase "bind hosts" $ do
        bindHost LoopbackOnly @?= "127.0.0.1"
        bindHost HomeNetwork @?= "0.0.0.0"
    ]
