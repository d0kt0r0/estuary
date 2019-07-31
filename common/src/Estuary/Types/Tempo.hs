{-# LANGUAGE DeriveDataTypeable #-}

module Estuary.Types.Tempo where

import Text.JSON
import Text.JSON.Generic
import Data.Time.Clock
import Data.Time.Clock.POSIX

data Tempo = Tempo {
  cps :: Rational,
  at :: UTCTime,
  beat :: Rational
  } deriving (Eq,Data,Typeable,Show)

instance JSON Tempo where
  showJSON = toJSON
  readJSON = fromJSON

utcTimeFromAudioClock :: UTCTime -> Double -> Double -> UTCTime
utcTimeFromAudioClock t0utc t0audio t1audio = posixSecondsToUTCTime $ clockDiff + (realToFrac t1audio)
  where clockDiff = utcTimeToPOSIXSeconds t0utc - (realToFrac t0audio)

elapsedCycles :: Tempo -> UTCTime -> Rational
elapsedCycles t now = elapsedT * cps t + beat t
  where elapsedT = realToFrac $ diffUTCTime now (at t)

adjustCps :: Rational -> Tempo -> UTCTime -> Tempo
adjustCps newCps prevTempo now = Tempo { cps = newCps, at = now, beat = elapsedCycles prevTempo now }

adjustCpsNow :: Rational -> Tempo -> IO Tempo
adjustCpsNow newCps prevTempo = getCurrentTime >>= return . adjustCps newCps prevTempo

beatZero :: Tempo -> UTCTime
beatZero x = addUTCTime (realToFrac $ beat x * (-1) / cps x) (at x)

adjustByClockDiff :: UTCTime -> Tempo -> IO Tempo
adjustByClockDiff x t = do
  tSystem <- getCurrentTime
  let clockDiff = diffUTCTime tSystem x
  return $ t {
    at = addUTCTime (clockDiff*(-1)) (at t)
  }
