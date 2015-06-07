module Handler.ChessSpec (spec) where

import TestImport

spec :: Spec
spec = withApp $ do
    describe "postNewGameR" $
      it "adds a new game to the database" $ do
          games <- runDB $ selectList ([] :: [Filter Game]) []
          assertEqual "game table starts empty" 0 $ length games
          post NewGameR
          statusIs 303
          games' <- runDB $ selectList ([] :: [Filter Game]) []
          assertEqual "game table contains new game" 1 $ length games'
    describe "postJoinR" $
      -- once someone "joins" a game (receives the black password), we don't want
      -- anyone else to be able to join, so we set the joinCode to Nothing
      it "removes joinCode from the database" $ do
        post NewGameR
        statusIs 303
        Just (Entity gameId (Game (Just jc) _ _ _)) <- runDB $ selectFirst ([] :: [Filter Game]) []
        post $ JoinR gameId jc
        statusIs 303
        Just (Entity _ (Game joinCode _ _ _)) <- runDB $ selectFirst ([] :: [Filter Game]) []
        assertEqual "joinCode is Nothing" joinCode Nothing
