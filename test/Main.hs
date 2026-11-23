module Main (main) where

import System.Environment (lookupEnv)
import Test.Tasty

import qualified BitboardTests
import qualified GoldenTests
import qualified ReferenceTests
import qualified ToolchainTests

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
      ]
