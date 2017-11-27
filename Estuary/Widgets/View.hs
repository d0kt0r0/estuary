{-# LANGUAGE RecursiveDo #-}

module Estuary.Widgets.View where

import qualified Data.Map as Map
import Control.Monad
import Reflex
import Reflex.Dom

import Estuary.Types.Response
import Estuary.Types.Definition
import Estuary.Types.Request
import Estuary.Types.View
import Estuary.Types.Sited
import Estuary.Types.EnsembleRequest
import Estuary.Types.EnsembleResponse
import Estuary.Types.EnsembleState
import Estuary.Types.Hint
import Estuary.Types.EditOrEval
import Estuary.Types.Terminal
import Estuary.Tidal.Types
import Estuary.Utility

import Estuary.Widgets.TransformedPattern
import Estuary.Widgets.Text
import Estuary.Widgets.Terminal

viewInEnsembleWidget :: MonadWidget t m =>
  String -> Event t Command -> Event t [ServerResponse] ->
  m (Dynamic t DefinitionMap, Event t ServerRequest, Event t Hint)

viewInEnsembleWidget ensemble commands deltasDown = mdo

  -- UI for global ensemble parameters
  divClass "ensembleName" $ text $ "Ensemble: " ++ ensemble
  hdl <- divClass "handleInEnsemble" $ do
    text "   Name/Handle:"
    let attrs = constDyn ("class" =: "webSocketTextInputs")
    handleInput <- textInput $ def & textInputConfig_attributes .~ attrs
    return $ _textInput_input handleInput
  pwdRequest <- divClass "ensemblePassword" $ do
    text "   Ensemble Password:"
    let attrs = constDyn ("class" =: "webSocketTextInputs")
    pwdInput <- textInput $ def & textInputConfig_inputType .~ "password" & textInputConfig_attributes .~ attrs
    return $ fmap AuthenticateInEnsemble $ _textInput_input pwdInput

  -- management of EnsembleState
  let initialState = newEnsembleState ensemble
  let commandChanges = fmap commandsToStateChanges commands
  let ensembleResponses = fmap (justSited ensemble . justEnsembleResponses) deltasDown
  let responseChanges = fmap ((foldl (.) id) . fmap responsesToStateChanges) ensembleResponses
  let handleChanges = fmap (\x es -> es { userHandle = x}) hdl
  let requestChanges = fmap requestsToStateChanges edits
  ensembleState <- foldDyn ($) initialState $ mergeWith (.) [commandChanges,responseChanges,handleChanges,requestChanges]

  -- dynamic View UI
  let initialWidget = viewWidget emptyView Map.empty ensembleResponses
  currentView <- liftM nubDyn $ mapDyn getActiveView ensembleState
  let newView = updated currentView
  currentDefs <- mapDyn zones ensembleState
  let newDefsAndView = attachDyn currentDefs newView
  let rebuildWidget = fmap (\(ds,v) -> viewWidget v ds ensembleResponses) newDefsAndView
  ui <- widgetHold initialWidget rebuildWidget
  defMap <- liftM joinDyn $ mapDyn (\(y,_,_) -> y) ui
  edits <- liftM switchPromptlyDyn $ mapDyn (\(_,y,_) -> y) ui
  hints <- liftM switchPromptlyDyn $ mapDyn (\(_,_,y) -> y) ui

  -- form requests to send to server
  joinRequest <- liftM (JoinEnsemble ensemble <$) $ getPostBuild
  let commandRequests = attachDynWithMaybe commandsToRequests ensembleState commands
  let ensembleRequests = fmap (EnsembleRequest . Sited ensemble) $ leftmost [edits,pwdRequest,commandRequests]
  let requests = leftmost [joinRequest,ensembleRequests]
  return (defMap,requests,hints)


viewInSoloWidget :: MonadWidget t m => View -> m (Dynamic t DefinitionMap, Event t Hint)
viewInSoloWidget view = do
  (zones,edits,hints) <- viewWidget view Map.empty never
  return (zones,hints)


viewWidget :: MonadWidget t m => View -> DefinitionMap -> Event t [EnsembleResponse Definition] ->
  m (Dynamic t DefinitionMap, Event t (EnsembleRequest Definition), Event t Hint)

viewWidget (Views xs) initialDefs deltasDown = foldM f i xs
  where
    i = (constDyn (Map.empty :: DefinitionMap), never, never)
    f b a = do
      let (prevZoneMap,prevEdits,prevHints) = b
      (zoneMap,edits,hints) <- viewWidget a initialDefs deltasDown
      newZoneMap <- combineDyn Map.union prevZoneMap zoneMap
      let newEdits = leftmost [prevEdits,edits]
      let newHints = leftmost [prevHints,hints]
      return (newZoneMap,newEdits,newHints)

viewWidget (ViewDiv c v) i deltasDown = divClass c $ viewWidget v i deltasDown

viewWidget (StructureView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure EmptyTransformedPattern) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- topLevelTransformedPatternWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (TidalTextView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (MiniTidalPattern "")) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- miniTidalWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (CQenzeView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (CQenzePattern "")) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- cqenzeWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (LabelView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (LabelText "") n i
  let deltasDown' = fmap (justLabelTexts . justEditsInZone n) deltasDown
  edits <- labelWidget i' deltasDown'
  let edits' = fmap (ZoneRequest . Sited n) edits
  return (constDyn Map.empty,edits',never)
  where f (LabelText x) = x
        f _ = ""

viewWidget (EvaluableTextView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (EvaluableText "") n i
  let deltasDown' = fmap (justEvaluableTexts . justEditsInZone n) deltasDown
  editsOrEvals <- evaluableTextWidget i' deltasDown'
  let editsOrEvals' = fmap (ZoneRequest . Sited n) editsOrEvals
  return (constDyn Map.empty,editsOrEvals',never)
  where f (EvaluableText x) = x
        f _ = ""