{-# LANGUAGE RecursiveDo, OverloadedStrings #-}

module Estuary.Widgets.AudioMap (audioMapWidget) where

import Reflex
import Reflex.Dom
import Data.Map
import Data.Text
import TextShow
import Data.List (nub)

import Estuary.Widgets.Editor
import Estuary.Types.Context
import Estuary.Types.ResourceMap
import Estuary.Types.AudioResource

audioMapWidget :: MonadWidget t m => Editor t m ()
audioMapWidget = elClass "div" "reference" $ do
  ctx <- context
  aMap <- holdUniqDyn $ fmap audioMap ctx
  simpleList (reduceAudioMap <$> aMap) builder
  return ()

reduceAudioMap :: Map (Text,Int) AudioResource -> [(Text,Int)]
reduceAudioMap x =
  let allNames = fmap fst $ keys x -- with duplicates
      sNames = nub allNames -- without duplicates
      sCounts = fmap (countName allNames) sNames
  in Prelude.zip sNames sCounts

countName :: [Text] -> Text -> Int
countName haystack needle = Prelude.length $ Prelude.filter (==needle) haystack

builder :: MonadWidget t m => Dynamic t (Text,Int)-> m ()
builder x = el "div" $ dynText $ fmap (\(sName,sCount) -> sName <> " (" <> showt sCount <> " samples)") x
