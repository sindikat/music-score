

{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE StandaloneDeriving #-}

module Music.Score.Export.Lilypond2 where

import Music.Pitch.Literal
import Music.Score hiding (
  toLilypond,
  toLilypondString
  )
import qualified Music.Lilypond as Lilypond
import qualified Text.Pretty                  as Pretty
import           Music.Score.Export.Common
import Data.Ratio
import Data.Maybe
import Data.Foldable (Foldable)
import Data.Traversable (Traversable, sequenceA)

{-
  Assume that Music is a type function that returns the underlying music
  representation for a given backend.

  Then, for each backend B we need to provide a function
    s a -> Music B
  where s is some score-like type constructor, and a is some note-like type.
  From a we need to fetch each aspect:
    pitch
    dynamic
    articulation
    part
  and convert it to the relevant representation of that aspect in B.
  For example with lilypond we need to convert to LilypondPitch, LilypondDynamic etc.
  Then we need to take s and convert it into some kind of fold for the musical types
  (usually a set of parallel, seequential compositions). Apply the folds, and we're done.
  
  
  
  
  

  chord
  behavior
  tie
  slide

  tremolo
  harmonic
  text
  clef
-}

-- TODO remove this somehow
-- type HasOrdPart a = (HasPart' a, Ord (Part a), Transformable a)
type HasOrdPart a = (a ~ a)



-- |
-- This class defines types and functions for exporting music in a very general way.
--
-- The backend type @b@ is just a type level tag to identify a specific backend,
-- typically defines as an empty data declaration:
--
-- @
-- data Foo
-- instance HasBackend Foo where
--   type BackendMusic Foo = ...
-- @
--
-- The actual conversion is handled by the subclasses 'HasBackendScore' and 'HasBackendEvent',
-- which converts the time structure, and the contained music respectively. In general, parametricity ensures
-- that structure and content are handled completely separately. However, it is often necessary to
-- alter the events based on their surrounding context: for examples the beginning and end of spanners
-- and beams depend on surrounding notes. Thus, the 'BackendContext' type allow 'HasBackendScore' instances
-- to provide context for 'HasBackendEvent' instances.
--
--
--
class Functor (BackendScore b) => HasBackend b where
  -- | The full music representation
  type BackendMusic b :: *

  -- | Score, voice and time structure, with output handled by 'HasBackendScore' 
  type BackendScore b :: * -> *

  -- | Notes, chords and rests, with output handled by 'HasBackendEvent' 
  type BackendEvent b :: *

  -- | This type may be used to pass context from 'exportScore' to 'exportNote'.
  --   Often will typically include duration, onset or surrounding notes.
  --
  --   If the note export is not context-sensitive, 'Identity' can be used.
  type BackendContext b :: * -> *

  finalizeExport :: b -> BackendScore b (BackendEvent b) -> BackendMusic b
  
class (HasBackend b, Functor s) => HasBackendScore b s where
  exportScore :: HasOrdPart a => b -> s a -> BackendScore b (BackendContext b a)
  -- default exportScore :: (BackendContext b ~ Identity) => b -> s a -> BackendScore b (BackendContext b a)
  -- exportScore b = fmap Identity

class (HasBackend b) => HasBackendEvent b a where
  exportNote  :: b -> BackendContext b a   -> BackendEvent b
  exportChord :: b -> BackendContext b [a] -> BackendEvent b
  exportChord = error "Not implemented"

  -- exportNote' :: (BackendContext b ~ Identity) => b -> a -> BackendEvent b
  -- exportNote' b x = exportNote b (Identity x)

export :: (HasOrdPart a, HasBackendScore b s, HasBackendEvent b a) => b -> s a -> BackendMusic b
export b = finalizeExport b . export'
  where
    -- These commute except for BackendContext

    -- There seems to be a bug in ghc 7.6.3 that allow us to rearrange the two
    -- composed functions, event though the precence of (BackendContext b) clearly
    -- prevents this:
    export' = fmap (exportNote b) . exportScore b
    
    -- The offending version:
    -- export' = exportScore b . fmap (exportNote b)



data Foo
instance HasBackend Foo where
  type BackendScore Foo     = []
  type BackendContext Foo   = Identity
  type BackendEvent Foo     = [(Sum Int, Int)]
  type BackendMusic Foo     = [(Sum Int, Int)]
  finalizeExport _ = concat
instance HasBackendScore Foo [] where
  exportScore _ = fmap Identity
instance HasBackendEvent Foo a => HasBackendEvent Foo [a] where
  -- exportNote b (Identity ps) = concatMap (exportNote b . Identity) ps
  exportNote b ps = mconcat $ map (exportNote b) $ sequenceA ps
instance HasBackendEvent Foo Int where
  exportNote _ (Identity p) = [(mempty ,p)]
instance HasBackendEvent Foo a => HasBackendEvent Foo (DynamicT (Sum Int) a) where
  exportNote b (Identity (DynamicT (d,ps))) = set (mapped._1) d $ exportNote b (Identity ps)

-- main = print $ export (undefined::Foo) [DynamicT (Sum 4::Sum Int,3::Int), pure 1]





-- type Lilypond = Lilypond.Music
toLilypondString :: (HasOrdPart a, HasBackendEvent Ly a, HasBackendScore Ly s) => s a -> String
toLilypondString = show . Pretty.pretty . toLilypond

toLilypond :: (HasOrdPart a, HasBackendEvent Ly a, HasBackendScore Ly s) => s a -> Lilypond.Music
toLilypond = export (undefined::Ly)

data Ly
data LyScore a = LyScore [[a]] deriving (Functor, Eq, Show)
data LyContext a = LyContext Duration a deriving (Functor, Foldable, Traversable, Eq, Show)
instance Monoid Lilypond.Music where
  mempty = pcatLilypond []
  mappend x y = pcatLilypond [x,y]

instance HasBackend Ly where
  type BackendScore Ly = LyScore
  type BackendContext Ly = LyContext
  type BackendEvent Ly = Lilypond.Music
  type BackendMusic Ly = Lilypond.Music
  finalizeExport _ (LyScore xs) = pcatLilypond . fmap scatLilypond $ xs


instance HasBackendScore Ly Score where
  -- exportScore b s = exportScore b ((^?! phrases) s)
  exportScore b s = exportScore b (fmap fromJust $ (^?! singleMVoice) $ s)
instance HasBackendScore Ly Voice where
  exportScore _ v = LyScore [map (\(d,x) -> LyContext d x) $ view eventsV v]

instance HasBackendEvent Ly a => HasBackendEvent Ly [a] where
  -- exportNote b ps = mconcat $ map (exportNote b) $ sequenceA ps
  exportNote b = exportChord b

instance HasBackendEvent Ly Integer where
  -- exportNote _ (LyContext d [])  = (^*realToFrac (d*4)) . Lilypond.rest
  exportNote _ (LyContext d x) = (^*realToFrac (d*4)) . Lilypond.note  . spellLilypond $ x
  exportChord _ (LyContext d xs)  = (^*realToFrac (d*4)) . Lilypond.chord . fmap spellLilypond $ xs


instance HasBackendEvent Ly Int where 
  exportNote b = exportNote b . fmap toInteger

instance HasBackendEvent Ly Float where 
  exportNote b = exportNote b . fmap (toInteger . round)

instance HasBackendEvent Ly Double where 
  exportNote b = exportNote b . fmap (toInteger . round)

instance Integral a => HasBackendEvent Ly (Ratio a) where 
  exportNote b = exportNote b . fmap (toInteger . round)

instance HasBackendEvent Ly a => HasBackendEvent Ly (Behavior a) where
  exportNote b = exportNote b . fmap (! 0)

instance HasBackendEvent Ly a => HasBackendEvent Ly (Sum a) where
  exportNote b = exportNote b . fmap getSum

instance HasBackendEvent Ly a => HasBackendEvent Ly (Product a) where
  exportNote b = exportNote b . fmap getProduct

instance HasBackendEvent Ly a => HasBackendEvent Ly (PartT n a) where
  exportNote b = exportNote b . fmap (snd . getPartT)

-- TODO ties
-- TODO dynamics
instance HasBackendEvent Ly a => HasBackendEvent Ly (DynamicT n a) where
  exportNote b = exportNote b . fmap (snd . getDynamicT)

instance HasBackendEvent Ly a => HasBackendEvent Ly (ArticulationT n a) where
  exportNote b = exportNote b . fmap (snd . getArticulationT)
  
instance HasBackendEvent Ly a => HasBackendEvent Ly (TremoloT a) where
  exportNote b (LyContext d (TremoloT (n, x))) = exportNote b $ LyContext d x -- TODO many
    -- where
    -- getL d (TremoloT (Max 0, x)) = exportNote b (LyContext d [x])
    -- getL d (TremoloT (Max n, x)) = notate $ getLilypond newDur x
    --     where
    --         scale   = 2^n
    --         newDur  = (d `min` (1/4)) / scale
    --         repeats = d / newDur
    --         notate = Lilypond.Tremolo (round repeats)

instance HasBackendEvent Ly a => HasBackendEvent Ly (TextT a) where
  exportNote b (LyContext d (TextT (n, x))) = notate n (exportNote b $ LyContext d x) -- TODO many
    where
      notate ts = foldr (.) id (fmap Lilypond.addText ts)

-- TODO harmonic
-- TODO slide
-- TODO clef








pcatLilypond :: [Lilypond] -> Lilypond
pcatLilypond = pcatLilypond' False

pcatLilypond' :: Bool -> [Lilypond] -> Lilypond
pcatLilypond' p = foldr Lilypond.simultaneous e
    where
        e = Lilypond.Simultaneous p []

scatLilypond :: [Lilypond] -> Lilypond
scatLilypond = foldr Lilypond.sequential e
    where
        e = Lilypond.Sequential []

spellLilypond :: Integer -> Lilypond.Note
spellLilypond a = Lilypond.NotePitch (spellLilypond' a) Nothing

spellLilypond' :: Integer -> Lilypond.Pitch
spellLilypond' p = Lilypond.Pitch (
    toEnum $ fromIntegral pc,
    fromIntegral alt,
    fromIntegral oct
    )
    where (pc,alt,oct) = spellPitch (p + 72)





main = putStrLn $ toLilypondString $ simultaneous $ scat [c,d,e::Score [Integer]] <> fs