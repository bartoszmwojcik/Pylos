-- | @pylos-web@: the live game server (S4).
--
-- > pylos-web [PORT] [WEB_DIR]
--
-- It listens on 127.0.0.1 only (N02: no public deployment). From a laptop,
-- reach it through an SSH tunnel: @ssh -L 8080:localhost:8080 server@.
module Main (main) where

import Data.String (fromString)
import qualified Network.Wai.Handler.Warp as Warp
import System.Environment (getArgs)
import System.IO (BufferMode (..), hSetBuffering, stdout)
import Text.Read (readMaybe)

import Pylos.Server.App (application)
import Pylos.Server.Games (newManager)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  let (port, webDir) = case args of
        [p, d] -> (maybe 8080 id (readMaybe p), d)
        [p] -> (maybe 8080 id (readMaybe p), "web")
        _ -> (8080, "web")
  mgr <- newManager
  app <- application mgr webDir
  putStrLn ("pylos-web: http://localhost:" ++ show port ++ "/ (serving " ++ webDir ++ ")")
  let settings = Warp.setHost (fromString "127.0.0.1") (Warp.setPort port Warp.defaultSettings)
  Warp.runSettings settings app
