{-# LANGUAGE RecursiveDo #-}

module Estuary.Widgets.View where

import qualified Data.Map as Map
import Control.Monad
import Reflex
import Reflex.Dom
import Text.Read
import Data.Time.Clock

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
  String -> UTCTime -> Event t Command -> Event t [ServerResponse] ->
  m (Dynamic t DefinitionMap, Event t ServerRequest, Event t Hint)

viewInEnsembleWidget ensemble now commands deltasDown = mdo

  -- UI for global ensemble parameters
  (hdl,pwdRequest,tempoRequest) <- divClass "ensembleHeader" $ do
    divClass "ensembleName" $ text $ "Ensemble: " ++ ensemble
    hdl' <- divClass "ensembleHandle" $ do
      text "Name:"
      let attrs = constDyn ("class" =: "ensembleHandle")
      handleInput <- textInput $ def & textInputConfig_attributes .~ attrs
      return $ _textInput_input handleInput
    pwdRequest' <- divClass "ensemblePassword" $ do
      text "password:"
      let attrs = constDyn ("class" =: "ensemblePassword")
      pwdInput <- textInput $ def & textInputConfig_inputType .~ "password" & textInputConfig_attributes .~ attrs
      return $ fmap AuthenticateInEnsemble $ _textInput_input pwdInput
    tempoRequest' <- divClass "ensembleTempo" $ do
      text "Ensemble Tempo:"
      let attrs = constDyn ("class" =: "ensembleTempo")
      tempoInput <- textInput $ def & textInputConfig_attributes .~ attrs
      let newTempo = fmapMaybe (readMaybe :: String -> Maybe Double) $ _textInput_input tempoInput
      return $ fmap TempoChange newTempo
    return (hdl',pwdRequest',tempoRequest')

  -- management of EnsembleState
  let initialState = newEnsembleState ensemble now
  let commandChanges = fmap commandsToStateChanges commands
  let ensembleResponses = fmap (justSited ensemble . justEnsembleResponses) deltasDown
  let responseChanges = fmap ((foldl (.) id) . fmap responsesToStateChanges) ensembleResponses
  let handleChanges = fmap (\x es -> es { userHandle = x}) hdl
  let requestChanges = fmap requestsToStateChanges edits
  ensembleState <- foldDyn ($) initialState $ mergeWith (.) [commandChanges,responseChanges,handleChanges,requestChanges]

  tempoHints <- liftM (fmap TempoHint . updated . nubDyn) $ mapDyn tempo ensembleState

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
  hintsUi <- liftM switchPromptlyDyn $ mapDyn (\(_,_,y) -> y) ui
  let hints = leftmost [tempoHints,hintsUi] -- *** note: might this occasionally lose a hint?

  -- form requests to send to server
  joinRequest <- liftM (JoinEnsemble ensemble <$) $ getPostBuild
  let commandRequests = attachDynWithMaybe commandsToRequests ensembleState commands
  let ensembleRequests = fmap (EnsembleRequest . Sited ensemble) $ leftmost [edits,pwdRequest,tempoRequest,commandRequests]
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
  let i' = f $ Map.findWithDefault (Structure (MiniTidalPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- miniTidalWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (CQenzeView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (CQenzePattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- cqenzeWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (MoreliaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (MoreliaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- moreliaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (SaludosView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (SaludosPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- saludosWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (SentidosView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (SentidosPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- sentidosWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (ColombiaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (ColombiaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- colombiaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (SiView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (SiPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- siWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (SabortsView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (SabortsPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- sabortsWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (NaturalView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (NaturalPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- naturalWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (MedellinView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (MedellinPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- medellinWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (LaCalleView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (LaCallePattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- laCalleWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (MariaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (MariaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- mariaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern

viewWidget (CrudoView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (CrudoPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- crudoWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (PuntoyyaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (PuntoyyaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- puntoyyaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (SucixxxView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (SucixxxPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- sucixxxWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (VocesotrevezView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (VocesotrevezPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- vocesotrevezWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (ImaginaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (ImaginaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- imaginaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (AlobestiaView n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (AlobestiaPattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- alobestiaWidget i' deltasDown'
  value' <- mapDyn (Map.singleton n . Structure) value
  let edits' = fmap (ZoneRequest . Sited n . Edit . Structure) edits
  return (value',edits',hints)
  where f (Structure x) = x
        f _ = EmptyTransformedPattern


viewWidget (Test1View n) i deltasDown = do
  let i' = f $ Map.findWithDefault (Structure (Test1Pattern (Live "" L3))) n i
  let deltasDown' = fmap (justStructures . justEditsInZone n) deltasDown
  (value,edits,hints) <- test1Widget i' deltasDown'
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
