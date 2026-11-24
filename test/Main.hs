module Main (main) where

import System.Environment (lookupEnv)
import Test.Tasty

import qualified BitboardTests
import qualified BotTests
import qualified GoldenTests
import qualified ReferenceTests
import qualified ToolchainTests
import qualified WebArgsTests

main :: IO ()
main = do
  demo <- lookupEnv "PYLOS_DEMO_FAILURE"
  defaultMain $
    testGroup
      "pylos"
      [ ToolchainTests.tests (demo == Just "1")
      , ReferenceTests.tests
      , GoldenTests.tests
      , BitboardTests.tests
      , BotTests.tests
      , WebArgsTests.tests
      ]
