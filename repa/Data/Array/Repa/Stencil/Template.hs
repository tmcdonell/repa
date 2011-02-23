{-# LANGUAGE TemplateHaskell, QuasiQuotes, ParallelListComp #-}

-- | Template 
module Data.Array.Repa.Stencil.Template
	(stencil2)
where
import Data.Array.Repa.Index
import Language.Haskell.TH
import Language.Haskell.TH.Quote
import qualified Data.List	as List

-- | QuasiQuoter for producing a static stencil defintion.
--   
--   A definition like 
--  
--   @
--     [stencil2|  0 1 0
--                 1 0 1
--                 0 1 0 |] 
--   @
--   Is converted to:
--   
--   @
--     makeStencil2 
--        (\ix -> case ix of
--	            Z :. -1 :.  0  -> Just 1
--                  Z :.  0 :. -1  -> Just 1
--                  Z :.  0 :.  1  -> Just 1
--                  Z :.  1 :.  0  -> Just 1
--                  _              -> Nothing)
--   @
--
stencil2 :: QuasiQuoter
stencil2 = QuasiQuoter 
		{ quoteExp	= parseStencil2
		, quotePat	= undefined
		, quoteType	= undefined
		, quoteDec	= undefined }


-- | Parse a stencil definition.
--   TODO: make this more robust.
parseStencil2 :: String -> Q Exp
parseStencil2 str 
 = let	
	-- Determine the extent of the stencil based on the layout.
	-- TODO: make this more robust. In particular, handle blank
	--       lines at the start of the definition.
	line1 : _	= lines str
	sizeX		= fromIntegral $ length $ lines str
	sizeY		= fromIntegral $ length $ words line1
	
	-- TODO: this probably doesn't work for stencils who's extents are even.
	minX		= negate (sizeX `div` 2)
	minY		= negate (sizeY `div` 2)
	maxX		= sizeX `div` 2
	maxY		= sizeY `div` 2

	-- List of coefficients for the stencil.
	coeffs		= (List.map read $ words str) :: [Double]
	
   in	makeStencil2' sizeX sizeY
	 $ filter (\(_, _, v) -> v /= 0)
	 $ [ (fromIntegral y, fromIntegral x, toRational v)
		| y	<- [minX, minX + 1 .. maxX]
		, x	<- [minY, minY + 1 .. maxY]
		| v	<- coeffs ]


makeStencil2'
	:: Integer -> Integer
	-> [(Integer, Integer, Rational)]
	-> Q Exp

makeStencil2' sizeX sizeY coeffs
 = do	let makeStencil' = mkName "makeStencil2"
	let dot'	 = mkName ":."
	let just'	 = mkName "Just"
	ix'		<- newName "ix"
	z'		<- [p| Z |]
	
	return 
	 $ AppE  (VarE makeStencil' `AppE` (LitE (IntegerL sizeX)) `AppE` (LitE (IntegerL sizeY)))
	 $ LamE  [VarP ix']
	 $ CaseE (VarE ix') 
	 $   [ Match	(InfixP (InfixP z' dot' (LitP (IntegerL oy))) dot' (LitP (IntegerL ox)))
			(NormalB $ ConE just' `AppE` LitE (RationalL v))
			[] | (oy, ox, v) <- coeffs ]
	  ++ [Match WildP 
			(NormalB $ ConE (mkName "Nothing"))
			[]]
