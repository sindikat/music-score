
{-# LANGUAGE
    CPP,
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    FlexibleInstances,
    FlexibleContexts,
    ConstraintKinds,
    OverloadedStrings,
    MultiParamTypeClasses,
    NoMonomorphismRestriction,
    GeneralizedNewtypeDeriving #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-- Combinators for manipulating scores.
--
-------------------------------------------------------------------------------------


module Music.Score.Combinators (
        -- ** Preliminaries
        Monoid',
        HasEvents,
        Transformable,

        -- ** Composing scores
        (|>),
        (<|),
        scat,
        pcat,

        -- *** Special composition
        sustain,
        anticipate,

        -- ** Transforming scores
        -- *** Moving in time
        move,
        moveBack,
        startAt,
        stopAt,

        -- *** Stretching in time
        stretch,
        compress,
        stretchTo,
        retrograde,

        -- *** Rests
        removeRests,

        -- *** Repetition
        times,
        repeated,
        group,
        -- triplet,
        -- quadruplet,
        -- quintuplet,

        -- *** Mapping
        recompose,
        mapEvents,
        mapEventsSingle,
        mapFirst,
        mapLast,
        mapPhrase,
        mapPhraseSingle,

        -- ** Conversion
        scoreToVoice,
        voiceToScore,
        voiceToScore',
  ) where

import Control.Monad
import Control.Monad.Plus
import Data.Semigroup
import Data.String
import Data.Foldable (Foldable)
import Data.Traversable
import Data.VectorSpace
import Data.AffineSpace
import Data.Ratio
import Data.Pointed
import Data.Ord

import Music.Score.Track
import Music.Score.Voice
import Music.Score.Score
import Music.Score.Part
import Music.Time

import qualified Data.List as List

-- | 
-- This pseudo-class can be used in place of 'Monoid' whenever an additional 'Semigroup'
-- is needed. If 'Monoid' is changed to extend 'Semigroup' it will not be needed.
--
type Monoid' a    = (Monoid a, Semigroup a)

-- TODO names?
type Scalable t d a = (
    Stretchable a, Delayable a,
    AdditiveGroup t,
    AffineSpace t,
    Diff t ~ d,
    Time a ~ t,
    Duration a ~ d
    )

class (
    Stretchable s, Delayable s,
    HasOnset s, HasOffset s,
    AdditiveGroup (Time s),
    AffineSpace (Time s)
    ) => Transformable s where

{-
type Transformable t d a = (
    Stretchable a, Delayable a,
    AdditiveGroup t,
    AffineSpace t,
    HasOnset a, HasOffset a,
    Time a ~ t,
    Duration a ~ d
    )
-}

instance Transformable Score
instance Transformable Track


-- |
-- This pseudo-class denotes generalizes structures that can be decomposed into events
-- and reconstructed.
--
class (
    Performable s,
    MonadPlus s,
    Transformable s
    ) => HasEvents s where

{-
type HasEvents t d s a  = (
    Performable s,
    MonadPlus s,
    Transformable t d (s a)
    )
-}

instance HasEvents Score


-------------------------------------------------------------------------------------
-- Constructors
-------------------------------------------------------------------------------------

-- |
-- Create a score containing a single event.
--
-- This function uses the unit position (0, 1).
--
-- > a -> Score a
--
-- note :: Pointed s => a -> s a
note :: MonadPlus s => a -> s a
note = return

-- |
-- Create a score containing a rest at time zero of duration one.
--
-- This function uses the unit position (0, 1).
--
-- > Score (Maybe a)
--
-- rest :: Pointed s => s (Maybe a)
rest :: MonadPlus s => s (Maybe a)
rest = note Nothing

-- |
-- Create a note or a rest. This is an alias for 'mfromMaybe' with a nicer reading.
--
-- This function uses the unit position (0, 1).
--
-- > a -> Score a
--
noteRest :: MonadPlus s => Maybe a -> s a
noteRest = mfromMaybe

-- | Creates a score containing a chord.
--
-- This function uses the unit position (0, 1).
--
-- > [a] -> Score a
--
-- chord :: (Pointed s, Monoid (s a)) => [a] -> s a
chord :: (MonadPlus s, Monoid' (s a)) => [a] -> s a
chord = pcat . map note

-- | Creates a score containing the given elements, composed in sequence.
--
-- > [a] -> Score a
--
melody :: (MonadPlus s, Monoid' (s a), Transformable s) => [a] -> s a
melody = scat . map note

-- | Like 'melody', but stretching each note by the given factors.
--
-- > [(Duration, a)] -> Score a
--
melodyStretch :: (MonadPlus s, Monoid' (s a), Transformable s, d ~ Duration s) => [(d, a)] -> s a
melodyStretch = scat . map ( \(d, x) -> stretch d $ note x )

-- | Like 'chord', but delays each note the given amounts.
--
-- > [(Time, a)] -> Score a
--
chordDelay :: (MonadPlus s, Monoid (s a), Transformable s, t ~ Time s) => [(t, a)] -> s a
chordDelay = pcat . map (\(t, x) -> delay' t $ note x)

-- | Like 'chord', but delays and stretches each note the given amounts.
--
-- > [(Time, Duration, a)] -> Score a
--
chordDelayStretch :: (MonadPlus s, Monoid (s a), Transformable s, d ~ Duration s, t ~ Time s) => [(t, d, a)] -> s a
chordDelayStretch = pcat . map (\(t, d, x) -> delay' t . stretch d $ note x)

-------------------------------------------------------------------------------------
-- Transformations
-------------------------------------------------------------------------------------

-- |
-- Move a score forward in time. Equivalent to 'delay'.
--
-- > Duration -> Score a -> Score a
--
move :: (Delayable s, d ~ Duration s) => d -> s a -> s a
move = delay

-- |
-- Move a score backward in time. Negated verison of 'delay'
--
-- > Duration -> Score a -> Score a
--
moveBack :: (Delayable s, AdditiveGroup d, d ~ Duration s) => d -> s a -> s a
moveBack t = delay (negateV t)

-- |
-- Move a score so that its onset is at the specific time.
--
-- > Duration -> Score a -> Score a
--
startAt :: (HasOnset s, Delayable s, AffineSpace t, t ~ Time s) => t -> s a -> s a
t `startAt` x = (t .-. onset x) `delay` x

-- |
-- Move a score so that its offset is at the specific time.
--
-- > Duration -> Score a -> Score a
--
stopAt :: (HasOffset s, Delayable s, AffineSpace t, t ~ Time s) => t -> s a -> s a
t `stopAt`  x = (t .-. offset x) `delay` x

-- |
-- Compress (diminish) a score. Flipped version of '^/'.
--
-- > Duration -> Score a -> Score a
--
compress :: (Stretchable s, Fractional d, d ~ Duration s) => d -> s a -> s a
compress x = stretch (recip x)

-- |
-- Stretch a score to fit into the given duration.
--
-- > Duration -> Score a -> Score a
--
stretchTo :: (Stretchable s, HasDuration s, Fractional d, d ~ Duration s) => d -> s a -> s a
t `stretchTo` x = (t / duration x) `stretch` x


-------------------------------------------------------------------------------------
-- Composition
-------------------------------------------------------------------------------------

infixr 6 |>
infixr 6 <|

-- |
-- Compose in sequence.
--
-- To compose in parallel, use '<>'.
--
-- > Score a -> Score a -> Score a
(|>) :: (Semigroup (s a), AffineSpace (Time s), HasOnset s, HasOffset s, Delayable s) => s a -> s a -> s a
a |> b =  a <> startAt (offset a) b


-- |
-- Compose in reverse sequence.
--
-- To compose in parallel, use '<>'.
--
-- > Score a -> Score a -> Score a
(<|) :: (Semigroup (s a), AffineSpace (Time s), HasOnset s, HasOffset s, Delayable s) => s a -> s a -> s a
a <| b =  b |> a

-- |
-- Sequential concatentation.
--
-- > [Score t] -> Score t
scat :: (Monoid' (s a), AffineSpace (Time s), HasOnset s, HasOffset s, Delayable s) => [s a] -> s a
scat = foldr (|>) mempty

-- |
-- Parallel concatentation. A synonym for 'mconcat'.
--
-- > [Score t] -> Score t
pcat :: Monoid a => [a] -> a
pcat = mconcat


-- |
-- Like '<>', but scaling the second agument to the duration of the first.
--
-- > Score a -> Score a -> Score a
--
sustain :: (Fractional (Duration s), Semigroup (s a), Stretchable s, HasDuration s) => s a -> s a -> s a
x `sustain` y = x <> duration x `stretchTo` y

-- Like '<>', but truncating the second agument to the duration of the first.
-- prolong x y = x <> before (duration x) y

-- |
-- Like '|>' but with a negative delay on the second element.
--
-- > Duration -> Score a -> Score a -> Score a
--
anticipate :: (Semigroup (s a), Transformable s, d ~ Duration s, Ord d) => d -> s a -> s a -> s a
anticipate t a b =  a <> startAt (offset a .-^ t) b



--------------------------------------------------------------------------------
-- Structure
--------------------------------------------------------------------------------

-- |
-- Repeat exact amount of times.
--
-- > Duration -> Score Note -> Score Note
--
times :: (Monoid' (s a), Transformable s) => Int -> s a -> s a
times n a = replicate (0 `max` n) () `repeated` const a

-- |
-- Repeat once for each element in the list.
--
-- Example:
--
-- > repeated [1,2,1] (c^*)
--
-- Simple type:
--
-- > [a] -> (a -> Score Note) -> Score Note
--
repeated :: (Monoid' (s b), Transformable s) => [a] -> (a -> s b) -> s b
repeated = flip (\f -> scat . fmap f)


{-
repeatedIndex n = repeated [0..n-1]
repeatedTime  n = repeated $ fmap (/ n) [0..(n - 1)]
-}

-- |
-- Remove rests from a score.
--
-- This is just an alias for 'mcatMaybes' which reads better in certain contexts.
--
-- > Score (Maybe a) -> Score a
--
removeRests :: MonadPlus m => m (Maybe a) -> m a
removeRests = mcatMaybes

-- -- |
-- -- Repeat three times and scale down by three.
-- --
-- -- > Score a -> Score a
-- --
-- triplet :: (Monoid' (s a), Transformable t d s, Time s ~ TimeT) => s a -> s a
-- triplet = group 3
-- 
-- -- |
-- -- Repeat three times and scale down by three.
-- --
-- -- > Score a -> Score a
-- --
-- quadruplet :: (Monoid' (s a), Transformable t d s, Time s ~ TimeT) => s a -> s a
-- quadruplet  = group 4
-- 
-- -- |
-- -- Repeat three times and scale down by three.
-- --
-- -- > Score a -> Score a
-- --
-- quintuplet :: (Monoid' (s a), Transformable t d s, Time s ~ TimeT) => s a -> s a
-- quintuplet  = group 5

-- |
-- Repeat a number of times and scale down by the same amount.
--
-- > Duration -> Score a -> Score a
--
group :: (Monoid' (s a), Transformable s, Time s ~ TimeT) => Int -> s a -> s a
group n a = times n (toDurationT n `compress` a)

-- |
-- Reverse a score around its middle point.
--
-- > onset a    = onset (retrograde a)
-- > duration a = duration (retrograde a)
-- > offset a   = offset (retrograde a)
--
-- > Score a -> Score a

retrograde :: (HasEvents s, t ~ Time s, Num t, Ord t) => s a -> s a
retrograde = recompose . List.sortBy (comparing fst3) . fmap g . perform
    where
        g (t,d,x) = (-(t.+^d),d,x)

--------------------------------------------------------------------------------
-- Mapping and recomposition
--------------------------------------------------------------------------------

#define MAP_CONSTRAINT \
    HasPart' a, \
    HasEvents s

-- | Recompose a score.
--
-- This is the inverse of 'perform'
--
-- > [(Time, Duration, a)] -> Score a
--
recompose :: (MonadPlus s, Transformable s, d ~ Duration s, t ~ Time s) => [(t, d, a)] -> s a
recompose = msum . liftM eventToScore

-- |
-- Map over the events in a score.
--
-- > (Time -> Duration -> a -> b) -> Score a -> Score b
--
mapEvents :: (MAP_CONSTRAINT, t ~ Time s, d ~ Duration s) => (t -> d -> a -> b) -> s a -> s b
mapEvents f = mapParts (liftM $ mapEventsSingle f)

-- |
-- Equivalent to 'mapEvents' for single-voice scores.
-- Fails if the score contains overlapping events.
--
-- > (Time -> Duration -> a -> b) -> Score a -> Score b
--
mapEventsSingle :: (HasEvents s, t ~ Time s, d ~ Duration s) => (t -> d -> a -> b) -> s a -> s b
mapEventsSingle f sc = recompose . fmap (third' f) . perform $ sc


-- |
-- Map over the first, and remaining notes in each part.
--
-- If a part has only one notes, the first function is applied.
-- If a part has no notes, the given score is returned unchanged.
--
-- > (a -> b) -> (a -> b) -> Score a -> Score b
--
mapFirst :: (MAP_CONSTRAINT) => (a -> b) -> (a -> b) -> s a -> s b
mapFirst f g = mapPhrase f g g

-- |
-- Map over the last, and preceding notes in each part.
--
-- If a part has only one notes, the first function is applied.
-- If a part has no notes, the given score is returned unchanged.
--
-- > (a -> b) -> (a -> b) -> Score a -> Score b
--
mapLast :: (MAP_CONSTRAINT) => (a -> b) -> (a -> b) -> s a -> s b
mapLast f g = mapPhrase g g f

-- |
-- Map over the first, middle and last note in each part.
--
-- If a part has fewer than three notes the first takes precedence over the last,
-- and last takes precedence over the middle.
--
-- > (a -> b) -> (a -> b) -> (a -> b) -> Score a -> Score b
--
mapPhrase :: (MAP_CONSTRAINT) => (a -> b) -> (a -> b) -> (a -> b) -> s a -> s b
mapPhrase f g h = mapParts (liftM $ mapPhraseSingle f g h)

-- |
-- Equivalent to 'mapPhrase' for single-voice scores.
-- Fails if the score contains overlapping events.
--
-- > (a -> b) -> (a -> b) -> (a -> b) -> Score a -> Score b
--
mapPhraseSingle :: HasEvents s => (a -> b) -> (a -> b) -> (a -> b) -> s a -> s b
mapPhraseSingle f g h sc = recompose . mapFirstMiddleLast (third f) (third g) (third h) . perform $ sc

-- eventToScore :: Scalable t d a => (t, d, a) -> m a
eventToScore (t,d,x) = delay' t . stretch d $ return x

--------------------------------------------------------------------------------
-- Conversion
--------------------------------------------------------------------------------

-- |
-- Convert a score into a voice.
--
-- This function fails if the score contain overlapping events.
--
scoreToVoice :: Score a -> Voice (Maybe a)
scoreToVoice = Voice . fmap throwTime . addRests' . perform
    where
       throwTime (t,d,x) = (d,x)

-- |
-- Convert a voice into a score.
--
voiceToScore :: Voice a -> Score a
voiceToScore = scat . fmap g . getVoice
    where
        g (d,x) = stretch d (note x)

-- |
-- Convert a voice which may contain rests into a score.
--
voiceToScore' :: Voice (Maybe a) -> Score a
voiceToScore' = mcatMaybes . voiceToScore

-- TODO move this instance
instance Performable Voice where
    perform = perform . voiceToScore


--------------------------------------------------------------------------------

addRests' :: [(TimeT, DurationT, a)] -> [(TimeT, DurationT, Maybe a)]
addRests' = concat . snd . mapAccumL g 0
    where
        g u (t, d, x)
            | u == t    = (t .+^ d, [(t, d, Just x)])
            | u <  t    = (t .+^ d, [(u, t .-. u, Nothing), (t, d, Just x)])
            | otherwise = error "addRests: Strange prevTime"

-- |
-- Map over first, middle and last elements of list.
-- Biased on first, then on first and last for short lists.
--
mapFirstMiddleLast :: (a -> b) -> (a -> b) -> (a -> b) -> [a] -> [b]
mapFirstMiddleLast f g h = go
    where
        go []    = []
        go [a]   = [f a]
        go [a,b] = [f a, h b]
        go xs    = [f $ head xs]          ++ 
                   map g (tail $ init xs) ++ 
                   [h $ last xs]

delay' t = delay (t .-. zeroV)

fst3 (t, d, x) = t

third f (a,b,c) = (a,b,f c)
third' f (a,b,c) = (a,b,f a b c)

rotl []     = []
rotl (x:xs) = xs ++ [x]

rotr [] = []
rotr xs = last xs : init xs

rotated = go
    where
        go n as 
            | n >= 0 = iterate rotr as !! n
            | n <  0 = iterate rotl as !! abs n

