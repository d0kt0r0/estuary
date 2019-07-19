{-# LANGUAGE DeriveDataTypeable #-}

-- This type represents all messages that an Estuary server can send
-- to an Estuary client via WebSockets.

module Estuary.Types.Response where

import Data.Maybe (mapMaybe)
import Text.JSON
import Text.JSON.Generic
import Data.Time.Clock
import Data.Text

import Estuary.Utility
import Estuary.Types.Sited
import Estuary.Types.EnsembleResponse
import Estuary.Types.Definition

data Response =
  ResponseError Text | -- eg. ensemble login failure
  EnsembleList [Text] |
  JoinedEnsemble Text Text | -- ensemble username
  EnsembleResponse EnsembleResponse |
  ServerInfo Int UTCTime -- response to ClientInfo: serverClientCount pingTime (from triggering ClientInfo)
  deriving (Data,Typeable)

instance JSON Response where
  showJSON = toJSON
  readJSON = fromJSON

justEnsembleResponses :: [Response] -> [EnsembleResponse]
justEnsembleResponses = mapMaybe f
  where f (EnsembleResponse x) = Just x
        f _ = Nothing

justEnsembleList :: [Response] -> Maybe [Text]
justEnsembleList = lastOrNothing . mapMaybe f
  where f (EnsembleList x) = Just x
        f _ = Nothing

justServerInfo :: [Response] -> Maybe (Int,UTCTime)
justServerInfo = lastOrNothing . mapMaybe f
  where f (ServerInfo x y) = Just (x,y)
        f _ = Nothing
