-- | @pylos-web@: the live game server.
--
-- > pylos-web [--lan] [PORT] [WEB_DIR]
--
-- Without WEB_DIR it serves @./web@, else a @web@ folder next to the
-- executable, else @/usr/share/pylos/web@ (D26, 'resolveWebDir'), so an
-- installed @pylos-web@ starts from any folder.
--
-- By default it listens on 127.0.0.1 only (N05). From a laptop, reach it
-- through an SSH tunnel: @ssh -L 8080:localhost:8080 server@. With @--lan@
-- it listens on 0.0.0.0, so a phone on the home network can play (D20); it
-- then prints the addresses to open and a warning, because there is no
-- authentication.
module Main (main) where

import Control.Exception (SomeException, try)
import Data.String (fromString)
import qualified Network.Socket as Net
import qualified Network.Wai.Handler.Warp as Warp
import System.Directory (doesDirectoryExist)
import System.Environment (getArgs, getExecutablePath)
import System.FilePath (takeDirectory)
import System.Exit (exitWith, ExitCode (..))
import System.IO (BufferMode (..), hPutStrLn, hSetBuffering, stderr, stdout)

import Pylos.Server.App (application)
import Pylos.Server.Games (newManager)
import WebArgs

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  opts <- case parseArgs args of
    Right o -> pure o
    Left err -> do
      hPutStrLn stderr ("pylos-web: " ++ err)
      hPutStrLn stderr "usage: pylos-web [--lan] [PORT] [WEB_DIR]"
      exitWith (ExitFailure 2)
  let port = optPort opts
  exeDir <- takeDirectory <$> getExecutablePath
  found <- resolveWebDir doesDirectoryExist exeDir (optWebDir opts)
  webDir <- case found of
    Right d -> pure d
    Left err -> do
      hPutStrLn stderr ("pylos-web: " ++ err)
      exitWith (ExitFailure 2)
  mgr <- newManager
  app <- application mgr webDir
  putStrLn ("pylos-web: http://localhost:" ++ show port ++ "/ (serving " ++ webDir ++ ")")
  case optBind opts of
    LoopbackOnly -> putStrLn "pylos-web: listening on 127.0.0.1 only (use --lan for the home network)"
    HomeNetwork -> do
      putStrLn ("pylos-web: listening on 0.0.0.0:" ++ show port ++ " (--lan)")
      ips <- lanAddress
      mapM_ (\ip -> putStrLn ("pylos-web: on the home network open http://" ++ ip ++ ":" ++ show port ++ "/")) ips
      putStrLn "pylos-web: WARNING: anyone on this network can open the server and play; there is no password (D20)"
  let settings =
        Warp.setHost (fromString (bindHost (optBind opts))) (Warp.setPort port Warp.defaultSettings)
  Warp.runSettings settings app

-- | The IPv4 address the machine would use to reach the local network, if
-- any. A UDP socket is "connected" to a documentation address (192.0.2.1,
-- RFC 5737); this only asks the kernel to pick a route and sends no packet.
-- The socket's own address is then the primary LAN address. Only the primary
-- one is found (a machine with several interfaces may have more; @ip addr@
-- lists them). Any failure, such as no network, gives no address.
lanAddress :: IO [String]
lanAddress = do
  r <- try $ do
    addr : _ <- Net.getAddrInfo (Just Net.defaultHints {Net.addrSocketType = Net.Datagram}) (Just "192.0.2.1") (Just "9")
    sock <- Net.socket (Net.addrFamily addr) Net.Datagram Net.defaultProtocol
    Net.connect sock (Net.addrAddress addr)
    local <- Net.getSocketName sock
    Net.close sock
    case local of
      Net.SockAddrInet _ host -> pure [showIPv4 (Net.hostAddressToTuple host)]
      _ -> pure []
  pure (either (\e -> const [] (e :: SomeException)) id r)
  where
    showIPv4 (a, b, c, d) = show a ++ "." ++ show b ++ "." ++ show c ++ "." ++ show d
