
module Data.Repa.Array.Internals.Target
        ( Target (..),  TargetI
        , empty,        singleton
        , fromList,     fromListInto
        , generateMaybeS
        , generateEitherS)
where
import Data.Repa.Array.Generic.Index            as A
import Data.Repa.Array.Internals.Bulk           as A
import System.IO.Unsafe
import Control.Monad
import Prelude                                  as P


-- Target ---------------------------------------------------------------------
-- | Class of manifest array representations that can be constructed
--   in a random-access manner.
--
class Layout l => Target l a where

 -- | Mutable buffer for some array representation.
 data Buffer l a

 -- | Allocate a new mutable buffer for the given layout.
 --
 --   UNSAFE: The integer must be positive, but this is not checked.
 unsafeNewBuffer    :: l -> IO (Buffer l a)

 -- | Read an element from the mutable buffer.
 --
 --   UNSAFE: The index bounds are not checked.
 unsafeReadBuffer   ::  Buffer l a -> Int -> IO a

 -- | Write an element into the mutable buffer.
 --
 --   UNSAFE: The index bounds are not checked.
 unsafeWriteBuffer  ::  Buffer l a -> Int -> a -> IO ()

 -- | O(n). Copy the contents of a buffer that is larger by the given
 --   number of elements.
 --
 --   UNSAFE: The integer must be positive, but this is not checked.
 unsafeGrowBuffer   :: Buffer l a -> Int -> IO (Buffer l a)

 -- | O(1). Yield a slice of the buffer without copying.
 --
 --   UNSAFE: The given starting position and length must be within the bounds
 --   of the of the source buffer, but this is not checked.
 unsafeSliceBuffer  :: Int -> Int -> Buffer l a -> IO (Buffer l a)

 -- | O(1). Freeze a mutable buffer into an immutable Repa array.
 --
 --   UNSAFE: If the buffer is mutated further then the result of reading from
 --           the returned array will be non-deterministic.
 unsafeFreezeBuffer :: Buffer l a -> IO (Array l a)

 -- | O(1). Thaw an Array into a mutable buffer.
 --
 --   UNSAFE: The Array is no longer safe to use.
 unsafeThawBuffer   :: Array l a -> IO (Buffer l a)

 -- | Ensure the array is still live at this point.
 --   Sometimes needed when the mutable buffer is a ForeignPtr with a finalizer.
 touchBuffer        :: Buffer l a -> IO ()

 -- | O(1). Get the layout from a Buffer.
 bufferLayout       :: Buffer l a -> l

-- | Constraint synonym that requires an integer index space.
type TargetI l a  = (Target l a, Index l ~ Int)


-------------------------------------------------------------------------------
-- | O(1). An empty array of the given layout.
empty   :: TargetI l a
        => Name l -> Array l a
empty nDst
 = unsafePerformIO
 $ do   let lDst = create nDst 0
        buf     <- unsafeNewBuffer lDst
        unsafeFreezeBuffer buf
{-# INLINE empty #-}


-- | O(1). Create a new empty array containing a single element.
singleton 
        :: TargetI l a
        => Name l -> a -> Array l a
singleton nDst x
 = unsafePerformIO
 $ do   let lDst = create nDst 0
        buf     <- unsafeNewBuffer lDst
        unsafeWriteBuffer  buf 0 x
        unsafeFreezeBuffer buf
{-# INLINE singleton #-}


-- | O(length src). Construct a linear array from a list of elements.
fromList :: TargetI l a
         => Name l -> [a] -> Array l a
fromList nDst xx
 = let  len      = P.length xx
        lDst     = create nDst len
        Just arr = fromListInto lDst xx
   in   arr
{-# NOINLINE fromList #-}


-- | O(length src). Construct an array from a list of elements,
--   and give it the provided layout.
--
--   The `length` of the provided shape must match the length of the list,
--   else `Nothing`.
--
fromListInto    :: Target l a
                => l -> [a] -> Maybe (Array l a)
fromListInto lDst xx
 = unsafePerformIO
 $ do   let !len = P.length xx
        if   len /= size (extent lDst)
         then return Nothing
         else do
                !buf    <- unsafeNewBuffer    lDst
                zipWithM_ (unsafeWriteBuffer  buf) [0..] xx
                arr     <- unsafeFreezeBuffer buf
                return $ Just arr
{-# NOINLINE fromListInto #-}


-------------------------------------------------------------------------------
-- | Generate an array of the given length by applying a function to
--   every index, sequentially. If any element returns `Nothing`,
--   then `Nothing` for the whole array.
generateMaybeS
        :: TargetI l a
        => Name l -> Int -> (Int -> Maybe a) 
        -> Maybe (Array l a)

generateMaybeS !nDst !len get
 = unsafePerformIO
 $ do
        let lDst = create nDst len
        !buf    <- unsafeNewBuffer lDst

        let fill_generateMaybeS !ix
             | ix >= len
             = return ix

             | otherwise
             = case get ix of
                Nothing 
                 -> return ix

                Just x  
                 -> do  unsafeWriteBuffer buf ix $! x
                        fill_generateMaybeS (ix + 1)
            {-# INLINE fill_generateMaybeS #-}

        !pos    <- fill_generateMaybeS 0
        if pos < len
         then return Nothing
         else fmap Just $! unsafeFreezeBuffer buf
{-# INLINE generateMaybeS #-}


-- | Generate an array of the given length by applying a function to
--   every index, sequentially. If any element returns `Left`, 
--   then `Left` for the whole array.
generateEitherS
        :: TargetI l a
        => Name l -> Int -> (Int -> Either err a) 
        -> Either err (Array l a)

generateEitherS !nDst !len get
 = unsafePerformIO
 $ do
        let lDst = create nDst len
        !buf    <- unsafeNewBuffer lDst

        let fill_generateEitherS !ix
             | ix >= len
             = return Nothing

             | otherwise
             = case get ix of
                Left err 
                 -> return $ Just err

                Right x  
                 -> do  unsafeWriteBuffer buf ix $! x
                        fill_generateEitherS (ix + 1)
            {-# INLINE fill_generateEitherS #-}

        !mErr   <- fill_generateEitherS 0
        case mErr of
         Just err       -> return $ Left err
         Nothing        -> fmap Right $! unsafeFreezeBuffer buf
{-# INLINE generateEitherS #-}


