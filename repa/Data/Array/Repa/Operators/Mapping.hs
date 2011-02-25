{-# OPTIONS_HADDOCK hide #-}
{-# LANGUAGE NoMonomorphismRestriction, PatternGuards #-}

module Data.Array.Repa.Operators.Mapping
	( map
	, zipWith
	, (+^)
	, (-^)
	, (*^)
	, (/^))
where
import Data.Array.Repa.Internals.Elt
import Data.Array.Repa.Internals.Base
import Data.Array.Repa.Shape		as S
import qualified Data.Vector.Unboxed	as V
import qualified Prelude		as P
import Prelude				(($), (.), (+), (*), (+), (/), (-))

-- | Apply Partitioned worker function to each element of an array, 
--	yielding a new array with the same extent.
--
--   TODO: We'll probably need to unfold this some.
--
map	:: (Shape sh, Elt a, Elt b) 
	=> (a -> b)
	-> Array sh a
	-> Array sh b

{-# INLINE map #-}
map f (Array sh regions)
 = Array sh (mapRegions regions)

 where	{-# INLINE mapRegions #-}
	mapRegions rs
	 = case rs of
		[]		 -> []
		[r]		 -> [mapRegion r]
		[r1, r2] 	 -> [mapRegion r1, mapRegion r2]
		[r1, r2, r3]	 -> [mapRegion r1, mapRegion r2, mapRegion r3]
		[r1, r2, r3, r4] -> [mapRegion r1, mapRegion r2, mapRegion r3, mapRegion r4]
		_		 -> mapRegions' rs
		
	mapRegions' rs
	 = case rs of
		[]		 -> []
		(r : rs')	 -> mapRegion r : mapRegions' rs'
		
	{-# INLINE mapRegion #-}
	mapRegion (Region range gen)
	 = Region range (mapGen gen)
	
	{-# INLINE mapGen #-}
	mapGen gen
	 = case gen of
		GenManifest vec
		 -> GenDelayed (\ix -> f $ V.unsafeIndex vec $ S.toIndex sh ix)
		
		GenDelayed getElem
		 -> GenDelayed (f . getElem)
		
		GenCursor makeCursor shiftCursor loadElem
		 -> GenCursor makeCursor shiftCursor (f . loadElem)


-- | Combine two arrays, element-wise, with a binary operator.
--	If the extent of the two array arguments differ, 
--	then the resulting array's extent is their intersection.
zipWith :: (Shape sh, Elt a, Elt b, Elt c) 
	=> (a -> b -> c) 
	-> Array sh a
	-> Array sh b
	-> Array sh c

{-# INLINE zipWith #-}
zipWith f arr1 arr2
 = let	{-# INLINE getElem' #-}
	getElem' ix	= f (arr1 `unsafeIndex` ix) (arr2 `unsafeIndex` ix)

   in	fromFunction
		(S.intersectDim (extent arr1) (extent arr2))
		getElem'


{-# INLINE (+^) #-}
(+^)	= zipWith (+)

{-# INLINE (-^) #-}
(-^)	= zipWith (-)

{-# INLINE (*^) #-}
(*^)	= zipWith (*)

{-# INLINE (/^) #-}
(/^)	= zipWith (/)
