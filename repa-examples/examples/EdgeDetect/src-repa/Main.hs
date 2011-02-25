{-# LANGUAGE PackageImports, BangPatterns, QuasiQuotes, PatternGuards #-}
{-# OPTIONS -Wall -fno-warn-missing-signatures -fno-warn-incomplete-patterns #-}

-- | Canny edge detector
import Data.List
import Data.Word
import Control.Monad
import System.Environment
import Data.Array.Repa 			as R
import Data.Array.Repa.Stencil
import Data.Array.Repa.IO.BMP
import Data.Array.Repa.IO.Timing
import Prelude				hiding (compare)

type Image	= Array DIM2 Float

-- Constants ------------------------------------------------------------------
orientPosDiag	= 0	:: Float
orientVert	= 1	:: Float
orientNegDiag	= 2	:: Float
orientHoriz	= 3	:: Float
orientUndef	= 4	:: Float

edge False	= 0 	:: Float
edge True	= 200 	:: Float


-- Main routine ---------------------------------------------------------------
main 
 = do	args	<- getArgs
	case args of
	 [fileIn, fileOut]	-> run fileIn fileOut
	 _			-> putStr "repa-edgedetect <fileIn.bmp> <fileOut.bmp>"


run fileIn fileOut
 = do	arrInput 	<- liftM (force . either (error . show) id) 
			$ readImageFromBMP fileIn

	let loops	= 1

	arrInput `deepSeqArray` return ()
	(arrResult, tTotal)
	 <- time
	 $ do	arrGrey		<- timeStage loops "toGreyScale"  $ return $ toGreyScale    arrInput
		arrBluredX	<- timeStage loops "blurX" 	  $ return $ blurSepX       arrGrey
		arrBlured	<- timeStage loops "blurY" 	  $ return $ blurSepY       arrBluredX
		arrDX		<- timeStage loops "diffX"	  $ return $ gradientX      arrBlured
		arrDY		<- timeStage loops "diffY"	  $ return $ gradientY      arrBlured
		arrMag		<- timeStage loops "magnitude"    $ return $ gradientMag    arrDX arrDY
		arrOrient	<- timeStage loops "orientation"  $ return $ gradientOrient arrDX arrDY
		arrSupress	<- timeStage loops "suppress"     $ return $ suppress       arrMag arrOrient
		return arrSupress

	putStrLn $ "\nTOTAL\n" ++ prettyTime tTotal

	
	writeMatrixToGreyscaleBMP fileOut arrResult


-- | Wrapper to time each stage of the algorithm.
timeStage
	:: (Shape sh, Elt a)
	=> Int
	-> String 
	-> (IO (Array sh a))
	-> (IO (Array sh a))

{-# NOINLINE timeStage #-}
timeStage loops name fn
 = do	let burn !n
	     = do arr	<- fn
		  arr `deepSeqArray` return ()
		  if n == 0 then return arr
		            else burn (n - 1)
			
	(arrResult, t)
	 <- time $ do	arrResult' <- burn loops
		   	arrResult' `deepSeqArray` return arrResult'

	putStr 	$  name ++ "\n"
		++ unlines [ "  " ++ l | l <- lines $ prettyTime t ]

	return arrResult
	

-------------------------------------------------------------------------------
-- | RGB to greyscale conversion.
{-# NOINLINE toGreyScale #-}
toGreyScale :: Array DIM3 Word8 -> Array DIM2 Float
toGreyScale 
	arr@(Array _ [Region RangeAll (GenManifest _)])
  = arr `deepSeqArray` force2
  $ traverse arr
	(\(sh :. _) -> sh)
	(\get ix    -> rgbToLuminance 
				(get (ix :. 0))
				(get (ix :. 1))
				(get (ix :. 2)))

 where	{-# INLINE rgbToLuminance #-}
	rgbToLuminance :: Word8 -> Word8 -> Word8 -> Float
	rgbToLuminance r g b 
		= floatOfWord8 r * 0.3
		+ floatOfWord8 g * 0.59
		+ floatOfWord8 b * 0.11

	{-# INLINE floatOfWord8 #-}
	floatOfWord8 :: Word8 -> Float
	floatOfWord8 w8
	 	= fromIntegral (fromIntegral w8 :: Int)


-- | Separable Gaussian blur in the X direction.
{-# NOINLINE blurSepX #-}
blurSepX :: Array DIM2 Float -> Array DIM2 Float
blurSepX arr@(Array _ [Region RangeAll (GenManifest _)])	
	= arr `deepSeqArray` force2
	$ forStencil2  BoundClamp arr
	  [stencil2|	1 4 6 4 1 |]	

-- | Separable Gaussian blur in the Y direction.
{-# NOINLINE blurSepY #-}
blurSepY :: Array DIM2 Float -> Array DIM2 Float
blurSepY arr@(Array _ [Region RangeAll (GenManifest _)])	
	= arr `deepSeqArray` force2
	$ R.map (/ 256)
	$ forStencil2  BoundClamp arr
	  [stencil2|	1
	 		4
			6
			4
			1 |]	


-- | Compute gradient in the X direction.
{-# NOINLINE gradientX #-}
gradientX :: Image -> Image
gradientX img@(Array _ [Region RangeAll (GenManifest _)])
 	= img `deepSeqArray` force2
    	$ forStencil2 BoundClamp img
	  [stencil2|	-1  0  1
			-2  0  2
			-1  0  1 |]


-- | Compute gradient in the Y direction.
{-# NOINLINE gradientY #-}
gradientY :: Image -> Image
gradientY img@(Array _ [Region RangeAll (GenManifest _)])
	= img `deepSeqArray` force2
	$ forStencil2 BoundClamp img
	  [stencil2|	 1  2  1
			 0  0  0
			-1 -2 -1 |] 


-- | Compute magnitude of the vector gradient.
{-# NOINLINE gradientMag #-}
gradientMag :: Image -> Image -> Image
gradientMag
	dX@(Array _ [Region RangeAll (GenManifest _)])
	dY@(Array _ [Region RangeAll (GenManifest _)])
 = [dX, dY] `deepSeqArrays` force2
 $ R.zipWith magnitude  dX dY

 where	{-# INLINE magnitude #-}
	magnitude :: Float -> Float -> Float
	magnitude x y	= x * x + y * y


-- | Classify the orientation of the vector gradient.
{-# NOINLINE gradientOrient #-}
gradientOrient :: Image -> Image -> Image
gradientOrient
 	dX@(Array _ [Region RangeAll (GenManifest _)])
	dY@(Array _ [Region RangeAll (GenManifest _)])
 = [dX, dY] `deepSeqArrays` force2
 $ R.zipWith orientation dX dY

 where	{-# INLINE orientation #-}
	orientation :: Float -> Float -> Float
	orientation x y
 	 | x >= -40, x < 40
 	 , y >= -40, y < 40	= orientUndef

	 | otherwise
	 = let	-- determine the angle of the vector and rotate it around a bit
		-- to make the segments easier to classify.
		!d	= atan2 y x 
		!dRot	= (d - (pi/8)) * (4/pi)
	
		-- normalise angle to beween 0..8
		!dNorm	= if dRot < 0 then dRot + 8 else dRot

		-- doing tests seems to be faster than using floor.
	   in	if dNorm >= 4
		 then if dNorm >= 6
			then if dNorm >= 7
				then orientHoriz   -- 7
				else orientNegDiag -- 6

			else if dNorm >= 5
				then orientVert    -- 5
				else orientPosDiag -- 4

		 else if dNorm >= 2
			then if dNorm >= 3
				then orientHoriz   -- 3
				else orientNegDiag -- 2

			else if dNorm >= 1
				then orientVert    -- 1
				else orientPosDiag -- 0


-- | Suppress pixels which are not local maxima.
{-# NOINLINE suppress #-}
suppress :: Image -> Image -> Image
suppress   dMag@(Array _ [Region RangeAll (GenManifest _)]) 
	dOrient@(Array _ [Region RangeAll (GenManifest _)])
 = [dMag, dOrient] `deepSeqArrays` force2 
 $ traverse2 dMag dOrient const compare

 where	_ :. height :. width	= extent dMag
	
	{-# INLINE isBoundary #-}
	isBoundary i j 
         | i == 0 || j == 0     = True
	 | i == width  - 1	= True
	 | j == height - 1	= True
	 | otherwise            = False

	{-# INLINE compare #-}
	compare get1 get2 d@(sh :. i :. j)
         | isBoundary i j      = edge False 
         | o == orientHoriz    = isMaximum (get1 (sh :. i     :. j - 1)) (get1 (sh :. i     :. j + 1)) 
         | o == orientVert     = isMaximum (get1 (sh :. i - 1 :. j))     (get1 (sh :. i + 1 :. j)) 
         | o == orientPosDiag  = isMaximum (get1 (sh :. i - 1 :. j - 1)) (get1 (sh :. i + 1 :. j + 1)) 
         | o == orientNegDiag  = isMaximum (get1 (sh :. i - 1 :. j + 1)) (get1 (sh :. i + 1 :. j - 1)) 
         | otherwise           = edge False  
      
         where
          !o 		= get2 d  
          !intensity 	= get1 (Z :. i :. j)

	  {-# INLINE isMaximum #-}
          isMaximum intensity1 intensity2
            | intensity < intensity1 = edge False
            | intensity < intensity2 = edge False
            | otherwise              = edge True

