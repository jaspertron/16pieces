{-# LANGUAGE FlexibleInstances, ScopedTypeVariables #-}
module Handler.Chess (getHomeR, postNewGameR, getJoinR, postJoinR, postMoveR, getGameR) where

import Import
import Chess (GameState, Color(..), move, newGame, currentPlayer)
import Chess.FEN (writeFEN, readFEN)
import System.Random (newStdGen, randomRs)
import Data.Maybe(fromJust)
import qualified Data.Map as Map
import Control.Concurrent.STM (retry)

getHomeR :: Handler Html
getHomeR = defaultLayout $ do
  setTitle "Chess"
  toWidget [whamlet|
    <form method=post action=@{NewGameR}>
      <button .btn .btn-lg .btn-primary .center-block type=submit>New Game
  |]

-- | Create a new game. The player who creates the game will be white.
-- The white player will be given a URL to share with the black player.
postNewGameR :: Handler TypedContent
postNewGameR = do
  joincode <- Just <$> getRandStr
  blackPassword <- getRandStr
  whitePassword <- getRandStr
  let newgame = Game joincode blackPassword whitePassword $ pack $ writeFEN newGame
  gameId <- runDB $ insert newgame
  gameCache <- appGameCache <$> getYesod
  atomically $ writeCache gameCache gameId newgame
  redirect $ GameR gameId White whitePassword

getJoinR :: GameId -> JoinCode -> Handler Html
getJoinR gid joinCode = defaultLayout $ do
  setTitle "Chess"
  toWidget [whamlet|
    <form method=post action=@{JoinR gid joinCode}>
      <button .btn .btn-lg .btn-primary .center-block type=submit>Join Game
  |]

-- | Join the game as the black player.
-- We require a join code (instead of just using the black password) so that
-- the white player will never see the black password.
-- Once the we reveal the black password, the join code is invalidated (set to Nothing)
-- so that no one else (looking at you, white player) can learn the black password.
postJoinR :: GameId -> JoinCode -> Handler TypedContent
postJoinR gameId joincode = do
  pw <- runDB $ do
    Game mjc bpw _ _ <- get404 gameId
    case mjc of
      Nothing -> lift alreadyJoined
      Just jc -> do
        unless (joincode == jc) $ lift wrongJoinCode
        update gameId [GameJoinCode =. Nothing]
        return bpw
  redirect $ GameR gameId Black pw

-- | Submit a move. Move format examples:
--   "f2-f3"
--   "c7-c8(Q)" (pawn promotion to queen)
postMoveR :: GameId -> Color -> Password -> Move -> Handler Value
postMoveR gameId color password m = do
  game <- runDB $ get404 gameId
  unless (correctPassword game color password) wrongPassword
  when (opponentsTurn game color) notYourTurn
  gamestate <- getGamestate game
  case move gamestate $ unpack m of
    Just gamestate' -> do
      runDB $ update gameId [GameFen =. pack (writeFEN gamestate')]
      game' <- runDB $ get404 gameId
      gameCache <- appGameCache <$> getYesod
      atomically $ writeCache gameCache gameId game'
      return $ toJSON $ object ["fen" .= gameFen game']
    Nothing -> sendResponseStatus status400 $ toJSON $ object ["fen" .= gameFen game]

-- | Get the state of a game. If the parameter "longpoll" is present,
-- this will block until it's the player's turn
getGameR :: GameId -> Color -> Password -> Handler TypedContent
getGameR gameId color password = do
  longpoll <- isJust <$> lookupGetParam "longpoll"
  gameCache <- appGameCache <$> getYesod
  mgame <- atomically $ do
    mt :: Maybe (TVar Game) <- readCache gameCache gameId
    mg :: Maybe Game <- maybe (return Nothing) (fmap Just . readTVar) mt
    maybe (return Nothing) (\g -> if longpoll && opponentsTurn g color then retry else return $ Just g) mg
  game <- runDB $ get404 gameId
  when (isNothing mgame) (atomically $ writeCache gameCache gameId game)
  selectRep $ do
    provideRep $ return $ toJSON $ object ["fen" .= gameFen game, "joincode" .= gameJoinCode game]
    provideRep $ defaultLayout $ do
      setTitle "Chess"
      toWidget [whamlet|
        <div #chessboard>
        <h3 #status .text-center>
      |]
      addStylesheet $ StaticR css_chessboard_0_3_0_css
      addScript $ StaticR js_jquery_2_1_4_js
      addScript $ StaticR js_chessboard_0_3_0_js
      addScript $ StaticR js_chess_0_9_1_js
      addScript $ StaticR js_lodash_js
      addScript $ StaticR js_16pieces_js
      addScript $ StaticR js_bootstrap_js
      pawnPromotionWidget color
      toWidget $ [julius| buildGame(#{toJSON gameId}, #{toJSON password}, #{toJSON $ gameFen game}, #{toJSON $ toLower $ show color}); |]
      toWidget $ [cassius|
        #chessboard
          margin-left: auto
          margin-right: auto
          max-width: 600px
        .highlight
            -webkit-box-shadow: inset 0 0 1000px 0 mediumspringgreen
            -moz-box-shadow: inset 0 0 1000px 0 mediumspringgreen
            box-shadow: inset 0 0 1000px 0 mediumspringgreen
      |]
      when (color == White) $
        toWidget $ [whamlet|
          $maybe joincode <- gameJoinCode game
            <div #joincode-message>
              <h4 .text-center>Share this link with your opponent: 
                <span>@{JoinR gameId joincode}
          $nothing
        |]

pawnPromotionWidget :: Color -> Widget
pawnPromotionWidget color = do
  toWidget [cassius|
    #promotion-modal a
      cursor: pointer
    #promotion-modal ul
      display: flex
      flex-wrap: wrap
      justify-content: space-between
      padding: 0
      width: 100%
    #promotion-modal li
      display: block
      list-style-type: none
      padding: 20px
      margin-left: auto
      margin-right: auto
  |]
  toWidget [whamlet|
    <div #promotion-modal .modal .fade tabindex="-1" role=dialog>
      <div .modal-dialog .modal-md>
        <div .modal-content>
          <div .modal-header>
            <button type=button .close data-dismiss=modal>
              <span>×
            <h4 .modal-title>Choose a piece
          <div .modal-body>
            <ul>
              <li>
                <a #promotion-queen title=Queen>
                  <img src="/static/img/chesspieces/wikipedia/#{toPathPiece color}Q.svg">
              <li>
                <a #promotion-knight title=Knight>
                  <img src="/static/img/chesspieces/wikipedia/#{toPathPiece color}N.svg">
              <li>
                <a #promotion-rook title=Rook>
                  <img src="/static/img/chesspieces/wikipedia/#{toPathPiece color}R.svg">
              <li>
                <a #promotion-bishop title=Bishop>
                  <img src="/static/img/chesspieces/wikipedia/#{toPathPiece color}B.svg">
  |]

-- used for generating passwords and joincodes
getRandStr :: Handler Text
getRandStr = do
  gen <- lift newStdGen
  return $ pack $ take 10 $ randomRs ('a','z') gen

correctPassword :: Game -> Color -> Password -> Bool
correctPassword (Game _ bpw _ _) Black pw = pw == bpw
correctPassword (Game _ _ wpw _) White pw = pw == wpw

opponentsTurn :: Game -> Color -> Bool
opponentsTurn game color =
  let gamestate = (fromJust $ readFEN $ unpack $ gameFen game)
  in currentPlayer gamestate /= color

wrongPassword :: Handler a
wrongPassword = do
  content <- selectRep $ do
    provideRep $ return $ toJSON ("Wrong password" :: Text)
    provideRep $ defaultLayout $ toWidget [shamlet|<h1>Wrong password|]
  sendResponseStatus status400 content

notYourTurn :: Handler a
notYourTurn = do
  content <- selectRep $ do
    provideRep $ return $ toJSON ("It's not your turn" :: Text)
    provideRep $ defaultLayout $ toWidget [shamlet|<h1>It's not your turn|]
  sendResponseStatus status400 content

corruptGame :: Handler a
corruptGame = do
  content <- selectRep $ do
    provideRep $ return $ toJSON ("Game is corrupt" :: Text)
    provideRep $ defaultLayout $ toWidget [shamlet|<h1>Game is corrupt|]
  sendResponseStatus status500 content

alreadyJoined :: Handler a
alreadyJoined = do
  content <- selectRep $ do
    provideRep $ return $ toJSON ("Someone has already joined that game" :: Text)
    provideRep $ defaultLayout $ toWidget [whamlet|
      <h1 .text-center>Someone has already joined that game.
      <h4 .text-center>Start your own game?
      <form method=post action=@{NewGameR}>
        <button .btn .btn-lg .btn-primary .center-block type=submit>New Game
    |]
  sendResponseStatus status410 content

wrongJoinCode :: Handler a
wrongJoinCode = do
  content <- selectRep $ do
    provideRep $ return $ toJSON ("Wrong join code" :: Text)
    provideRep $ defaultLayout $ toWidget [shamlet|<h1>Wrong join code|]
  sendResponseStatus status400 content

readCache :: TVar (Map GameId (TVar Game)) -> GameId -> STM (Maybe (TVar Game))
readCache appGameCache gameId = do
  cache <- readTVar appGameCache
  return $ Map.lookup gameId cache

writeCache :: TVar (Map GameId (TVar Game)) -> GameId -> Game -> STM ()
writeCache appGameCache gameId game = do
  cache <- readTVar appGameCache
  let mtvar :: Maybe (TVar Game) = Map.lookup gameId cache
  case mtvar of
    Nothing -> do
      cacheitem <- newTVar game
      writeTVar appGameCache $ Map.insert gameId cacheitem cache
    Just tvar -> writeTVar tvar $! game

getGamestate :: Game -> Handler GameState
getGamestate g =
  case readFEN $ unpack $ gameFen g of
    Nothing -> do
      $(logError) $ "Corrupt game: " <> gameFen g
      corruptGame
    Just gs -> return gs
