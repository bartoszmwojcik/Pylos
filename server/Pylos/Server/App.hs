{-# LANGUAGE OverloadedStrings #-}

-- | The web application (S4, D16): the browser files, the JSON API and the
-- Server-Sent Events stream of @docs/web-protocol.md@.
--
-- The JSON API is written with scotty, one readable line per route. Two
-- things are plain WAI instead, placed in front of scotty: the static files
-- (a few lines, no extra library) and the event stream (it needs a
-- long-running response, which wai-extra's 'eventSourceAppIO' provides).
module Pylos.Server.App
  ( application
  ) where

import Control.Concurrent.STM
import Control.Monad (when)
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.Aeson as A
import Data.ByteString.Builder (lazyByteString, string8)
import Data.IORef
import qualified Data.Text as T
import Data.ByteString (ByteString)
import Network.HTTP.Types (hContentType, status200, status201, status400, status404)
import Network.Wai
import Network.Wai.EventSource (ServerEvent (..), eventSourceAppIO)
import System.Directory (doesFileExist)
import System.FilePath (takeExtension, (</>))
import Text.Read (readMaybe)
import qualified Web.Scotty as S

import Pylos.Bot (botKinds)
import Pylos.Server.Games
import Pylos.Server.Json (resultJson)

-- | The whole application, given the game manager and the directory of the
-- browser files (@web/@).
application :: Manager -> FilePath -> IO Application
application mgr webDir = do
  api <- S.scottyApp (routes mgr webDir)
  pure (staticFiles webDir (eventStream mgr api))

-- ---------------------------------------------------------------------------
-- JSON API (scotty)

routes :: Manager -> FilePath -> S.ScottyM ()
routes mgr webDir = do
  S.get "/" $ do
    S.setHeader "Content-Type" "text/html; charset=utf-8"
    S.file (webDir </> "index.html")

  S.get "/api/bots" $
    S.json [object ["kind" .= k, "example" .= e, "help" .= h] | (k, e, h) <- botKinds]

  S.get "/api/games" $ do
    games <- S.liftIO (listGames mgr)
    S.json (map (uncurry summaryJson) games)

  S.post "/api/games" $ do
    raw <- S.body
    case A.eitherDecode raw >>= validate of
      Left err -> bad err
      Right ng -> do
        started <- S.liftIO (startGame mgr ng)
        case started of
          Left err -> bad err
          Right gid -> do
            S.status status201
            S.json (object ["id" .= T.pack (show gid)])

  S.get "/api/games/:id" $ do
    gidText <- S.pathParam "id"
    found <- S.liftIO (maybe (pure Nothing) (lookupGame mgr) (readMaybe gidText))
    case found of
      Nothing -> notFound
      Just lg -> do
        (st, _) <- S.liftIO (watch lg)
        S.json (snapshotJson lg st)

  -- The human's move (S5, D18). The answer is the data of the move's
  -- @move@ event; the bot's reply arrives on the event stream.
  S.post "/api/games/:id/move" $ do
    gidText <- S.pathParam "id"
    found <- S.liftIO (maybe (pure Nothing) (lookupGame mgr) (readMaybe gidText))
    case found of
      Nothing -> notFound
      Just lg -> do
        raw <- S.body
        case A.eitherDecode raw of
          Left err -> bad ("bad request body: " ++ err)
          Right (MoveRequest text) -> do
            played <- S.liftIO (submitMove lg text)
            case played of
              Left why -> bad (rejectionText why)
              Right ev -> S.json ev
  where
    bad err = do
      S.status status400
      S.json (object ["error" .= T.pack err])
    notFound = do
      S.status status404
      S.json (object ["error" .= ("no such game" :: T.Text)])

-- | The body of @POST /api/games/:id/move@: @{"move": "a11-b22 x a12"}@.
newtype MoveRequest = MoveRequest String

instance A.FromJSON MoveRequest where
  parseJSON = A.withObject "move" $ \o -> MoveRequest <$> o A..: "move"

-- | The body of @POST /api/games@.
data NewGameRequest = NewGameRequest String String (Maybe Int) (Maybe Int)

instance A.FromJSON NewGameRequest where
  parseJSON = A.withObject "new game" $ \o ->
    NewGameRequest
      <$> o A..: "white"
      <*> o A..: "black"
      <*> o A..:? "delayMs"
      <*> o A..:? "plyCap"

-- | Check a request: both players parse (a bot spec or @human@), at most
-- one of them is human (D18), the delay and the cap are sane.
validate :: NewGameRequest -> Either String NewGame
validate (NewGameRequest w b d c) = do
  white <- either (Left . ("white: " ++)) Right (parsePlayer w)
  black <- either (Left . ("black: " ++)) Right (parsePlayer b)
  when (white == Human && black == Human) $
    Left "at most one player can be human (D18)"
  delay <- inRange "delayMs" 0 10000 (maybe 800 id d)
  cap <- inRange "plyCap" 1 2000 (maybe 300 id c)
  pure (NewGame white black delay cap)
  where
    inRange name lo hi v
      | v >= lo && v <= hi = Right v
      | otherwise = Left (name ++ " must be between " ++ show lo ++ " and " ++ show hi)

-- ---------------------------------------------------------------------------
-- Event stream (WAI)

-- | @GET /api/games/:id/events@: a snapshot first, then the game's events.
-- Every 15 seconds without an event a comment is sent, which keeps proxies
-- and SSH tunnels from closing an idle connection.
eventStream :: Manager -> Middleware
eventStream mgr next req respond = case pathInfo req of
  ["api", "games", gidText, "events"]
    | requestMethod req == "GET" -> do
        found <- maybe (pure Nothing) (lookupGame mgr) (readMaybe (T.unpack gidText))
        case found of
          Nothing -> respond (responseLBS status404 jsonHeader (encode (object ["error" .= ("no such game" :: T.Text)])))
          Just lg -> do
            (st, chan) <- watch lg
            pending <- newIORef (Just (sse "snapshot" (snapshotJson lg st)))
            let nextEvent = do
                  first <- readIORef pending
                  case first of
                    Just ev -> writeIORef pending Nothing >> pure ev
                    Nothing -> do
                      timer <- registerDelay 15000000
                      atomically $
                        (toServerEvent <$> readTChan chan)
                          `orElse` (readTVar timer >>= check >> pure (CommentEvent "keep-alive"))
            eventSourceAppIO nextEvent req respond
  _ -> next req respond
  where
    jsonHeader = [(hContentType, "application/json")]
    toServerEvent (MoveEvent v) = sse "move" v
    toServerEvent (EndEvent r) = sse "end" (object ["result" .= resultJson (Just r)])

sse :: String -> Value -> ServerEvent
sse name v = ServerEvent (Just (string8 name)) Nothing [lazyByteString (encode v)]

-- ---------------------------------------------------------------------------
-- Static files (WAI)

-- | @GET /static/<path>@: a file from the web directory. Paths containing
-- @..@ or hidden names are refused, so nothing outside it can be read.
staticFiles :: FilePath -> Middleware
staticFiles webDir next req respond = case pathInfo req of
  ("static" : parts)
    | requestMethod req == "GET" ->
        if null parts || any unsafe parts
          then respond (responseLBS status404 [] "not found")
          else do
            let path = foldl (</>) webDir (map T.unpack parts)
            exists <- doesFileExist path
            respond $
              if exists
                then responseFile status200 [(hContentType, mimeType path)] path Nothing
                else responseLBS status404 [] "not found"
  _ -> next req respond
  where
    unsafe p = T.null p || "." `T.isPrefixOf` p || ".." `T.isInfixOf` p || "/" `T.isInfixOf` p

-- | The content type of the few kinds of file the viewer uses.
mimeType :: FilePath -> ByteString
mimeType path = case takeExtension path of
  ".html" -> "text/html; charset=utf-8"
  ".js" -> "text/javascript; charset=utf-8"
  ".css" -> "text/css; charset=utf-8"
  ".json" -> "application/json"
  ".png" -> "image/png"
  ".svg" -> "image/svg+xml"
  ".woff2" -> "font/woff2"
  _ -> "application/octet-stream"
