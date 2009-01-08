{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, MultiParamTypeClasses, FlexibleInstances #-}
module DotProd where
import Data.Word
import Data.TypeNumbers
import Foreign.Marshal.Array(allocaArray, pokeArray)
import Foreign.Ptr
import Foreign.Storable
import LLVM.Core
import LLVM.ExecutionEngine

import Loop

mDotProd :: forall n a . (IsPowerOf2 n, IsTypeNumber n,
	                  IsPrimitive a, IsArithmetic a, IsFirstClass a, IsConst a, Num a,
	                  FunctionArgs (IO a) (CodeGenFunction a ()) (CodeGenFunction a ())
	                 ) =>
            CodeGenModule (Function (Word32 -> Ptr (Vector n a) -> Ptr (Vector n a) -> IO a))
mDotProd =
  createFunction ExternalLinkage $ \ size aPtr bPtr -> do
    s <- forLoop (valueOf 0) size (value (zero :: ConstValue (Vector n a))) $ \ i s -> do

        ap <- getElementPtr aPtr (i, ()) -- index into aPtr
        bp <- getElementPtr bPtr (i, ()) -- index into bPtr
        a <- load ap                     -- load element from a vector
        b <- load bp                     -- load element from b vector
        ab <- mul a b                    -- multiply them
        add s ab                         -- accumulate sum

    r <- forLoop (valueOf (0::Word32)) (valueOf (typeNumber (undefined :: n)))
                 (valueOf 0) $ \ i r -> do
        ri <- extractelement s i
        add r ri
    ret (r :: Value a)

type R = Float
type T = Vector (D4 End) R

main :: IO ()
main = do
    let mDotProd' = mDotProd
    writeFunction "DotProd.bc" mDotProd'

    ioDotProd <- simpleFunction mDotProd'
    let dotProd :: [T] -> [T] -> R
        dotProd a b =
         unsafePurify $
         withArrayLen a $ \ aLen aPtr ->
         withArrayLen b $ \ bLen bPtr ->
-- XXX something weird is going on here.  Without that putStr the result is wrong.
         putStr "" >>
         ioDotProd (fromIntegral (aLen `min` bLen)) aPtr bPtr


    let a = [1 .. 8]
        b = [4 .. 11]
    print $ dotProd (vectorize 0 a) (vectorize 0 b)
    print $ sum $ zipWith (*) a b

writeFunction :: String -> CodeGenModule a -> IO ()
writeFunction name f = do
    m <- newModule
    defineModule m f
    writeBitcodeToFile name m

withArrayLen :: (Storable a) => [a] -> (Int -> Ptr a -> IO b) -> IO b
withArrayLen xs act =
    let l = length xs in
    allocaArray (l+1) $ \ p -> do
    let p' = alignPtr p (alignment (head xs))
    pokeArray p' xs
    act l p'

class Vectorize n a where
    vectorize :: a -> [a] -> [Vector n a]

{-
instance (IsPrimitive a) => Vectorize (D1 End) a where
    vectorize _ [] = []
    vectorize x (x1:xs) = mkVector x1 : vectorize x xs
-}

instance (IsPrimitive a) => Vectorize (D2 End) a where
    vectorize _ [] = []
    vectorize x (x1:x2:xs) = mkVector (x1, x2) : vectorize x xs
    vectorize x xs = vectorize x $ xs ++ [x]

instance (IsPrimitive a) => Vectorize (D4 End) a where
    vectorize _ [] = []
    vectorize x (x1:x2:x3:x4:xs) = mkVector (x1, x2, x3, x4) : vectorize x xs
    vectorize x xs = vectorize x $ xs ++ [x]

instance (IsPrimitive a) => Vectorize (D8 End) a where
    vectorize _ [] = []
    vectorize x (x1:x2:x3:x4:x5:x6:x7:x8:xs) = mkVector (x1, x2, x3, x4, x5, x6, x7, x8) : vectorize x xs
    vectorize x xs = vectorize x $ xs ++ [x]
