{-# LANGUAGE PackageImports #-} 

-- | Reading and writing arrays as uncompressed 24 bit Windows BMP files.
module Data.Array.Repa.IO.BMP
	( readMatrixFromGreyscaleBMP
	, readComponentsFromBMP
	, readImageFromBMP
	, writeMatrixToGreyscaleBMP
	, writeComponentsToBMP
	, writeImageToBMP)
where
import qualified "dph-prim-par" Data.Array.Parallel.Unlifted 	as U
import Data.Array.Repa				as A
import Prelude					as P
import Codec.BMP
import Data.Word

-- Read -------------------------------------------------------------------------------------------
-- | Read a matrix from a `BMP` file.
--	Each pixel is converted to greyscale, normalised to [0..1] and used
--	as the corresponding array element. If anything goes wrong when loading the file then `Error`.
readMatrixFromGreyscaleBMP
	:: FilePath 		-- ^ Name of output file.
	-> IO (Either Error (Array DIM2 Double))

readMatrixFromGreyscaleBMP filePath
 = do	eComps	<- readComponentsFromBMP filePath
	case eComps of 
	 Left err	-> return $ Left err
  	 Right (arrRed, arrGreen, arrBlue)
 	  -> let arr	= force 
			$ A.fromFunction (extent arrRed)
			   (\ix -> sqrt ( (fromIntegral (arrRed   !: ix) / 255) ^ (2 :: Int)
					+ (fromIntegral (arrGreen !: ix) / 255) ^ (2 :: Int)
					+ (fromIntegral (arrBlue  !: ix) / 255) ^ (2 :: Int)))
	     in	arr `deepSeqArray` return (Right arr)
		

-- | Read RGB components from a BMP file.
--	Returns arrays of red, green and blue components, all with the same extent.
--	If anything goes wrong when loading the file then `Error`.
readComponentsFromBMP
	:: FilePath 		-- ^ Name of output file.
	-> IO (Either Error (Array DIM2 Word8, Array DIM2 Word8, Array DIM2 Word8))

{-# INLINE readComponentsFromBMP #-}
readComponentsFromBMP filePath
 = do	ebmp	<- readBMP filePath
	case ebmp of
	 Left err	-> return $ Left err
	 Right bmp	-> return $ Right (readComponentsFromBMP' bmp)

readComponentsFromBMP' bmp
 = let	(width, height) = bmpDimensions bmp

	arr		= A.fromByteString (Z :. height :. width * 4)
			$ unpackBMPToRGBA32 bmp

	shapeFn _ 	= Z :. height :. width

	arrRed	
	 = traverse arr shapeFn
		(\get (sh :. x) -> get (sh :. (x * 4)))

	arrGreen
	 = traverse arr shapeFn
		(\get (sh :. x) -> get (sh :. (x * 4 + 1)))

	arrBlue
	 = traverse arr shapeFn
		(\get (sh :. x) -> get (sh :. (x * 4 + 2)))
	
   in	(arrRed, arrGreen, arrBlue)


-- | Read a RGBA image from a BMP file.
--	In the returned array, the higher two dimensions are the height and width,
--	and the lower indexes the RGBA components. The A (alpha) value is always zero.
readImageFromBMP 
	:: FilePath
	-> IO (Either Error (Array DIM3 Word8))

readImageFromBMP filePath
 = do	ebmp	<- readBMP filePath
	case ebmp of
	 Left err	-> return $ Left err
	 Right bmp	-> return $ Right (readImageFromBMP' bmp)
	
readImageFromBMP' bmp
 = let	(width, height)	= bmpDimensions bmp
	arr		= fromByteString (Z :. height :. width :. 4)
			$ unpackBMPToRGBA32 bmp
   in	arr



-- Write ------------------------------------------------------------------------------------------
-- | Write a matrix to a BMP file.
--	Negative values are discarded. Positive values are normalised to the maximum 
--	value in the matrix and used as greyscale pixels.
writeMatrixToGreyscaleBMP 
	:: FilePath		-- ^ Name of input file.
	-> Array DIM2 Double	-- ^ Matrix of values (need not be normalised).
	-> IO ()

writeMatrixToGreyscaleBMP fileName arr
 = let	arrNorm		= normalisePositive01 arr

	scale :: Double -> Word8
	scale x		= fromIntegral (truncate (x * 255) :: Int)

	arrWord8	= A.map scale arrNorm
   in	writeComponentsToBMP fileName arrWord8 arrWord8 arrWord8
		

-- | Write RGB components to a BMP file.
--	All arrays must have the same extent, else `error`.
writeComponentsToBMP
	:: FilePath
	-> Array DIM2 Word8	-- ^ Red   components.
	-> Array DIM2 Word8	-- ^ Green components.
	-> Array DIM2 Word8	-- ^ Blue  components.
	-> IO ()

writeComponentsToBMP fileName arrRed arrGreen arrBlue
 | not $ (  extent arrRed   == extent arrGreen       
         && extent arrGreen == extent arrBlue)
 = error "Data.Array.Repa.IO.BMP.writeComponentsToBMP: arrays don't have same extent"

 | otherwise
 = do	let Z :. height :. width	
			= extent arrRed
		
	-- Build image data from the arrays.
	let arrAlpha	= fromFunction (extent arrRed) (\_ -> 255)
	let arrRGBA	= interleave4 arrRed arrGreen arrBlue arrAlpha
	let bmp		= packRGBA32ToBMP width height
			$ A.toByteString arrRGBA
	
	writeBMP fileName bmp


-- | Write a RGBA image to a BMP file.
--	The higher two dimensions are the height and width of the image, 
--	and the lowest dimension be 4, corresponding to the RGBA components of each pixel.
writeImageToBMP 
	:: FilePath
	-> Array DIM3 Word8
	-> IO ()

writeImageToBMP fileName arrImage
	| comps /= 4
	= error "Data.Array.Repa.IO.BMP: lowest order dimension must be 4"

	| otherwise
	= let 	bmp	= packRGBA32ToBMP height width 
			$ A.toByteString arrImage
	  in	writeBMP fileName bmp
	
	where	Z :. height :. width :. comps	
			= extent arrImage
	

-- Normalise --------------------------------------------------------------------------------------
-- | Normalise a matrix to to [0 .. 1], discarding negative values.
--	If the maximum value is 0 then return the array unchanged.
normalisePositive01
	:: (Shape sh, U.Elt a, Fractional a, Ord a)
	=> Array sh a
	-> Array sh a

{-# INLINE normalisePositive01 #-}
normalisePositive01 arr	
 = let	mx		= foldAll max 0 arr
   	elemFn x
	 | x >= 0	= x / mx
	 | otherwise	= x
   in	mx `seq`
	 if mx == 0 
	  then arr
	  else A.map elemFn arr

