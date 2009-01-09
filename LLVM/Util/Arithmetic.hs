{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE FlexibleInstances, ScopedTypeVariables, FlexibleContexts, UndecidableInstances, TypeSynonymInstances, MultiParamTypeClasses, FunctionalDependencies #-}
module LLVM.Util.Arithmetic(
    TValue,
    Cmp,
    (%==), (%/=), (%<), (%<=), (%>), (%>=),
    (%&&), (%||),
    (?),
    retrn,
    ArithFunction(..)
    ) where
import Data.Word
import Data.Int
import LLVM.Core

type TValue r a = CodeGenFunction r (Value a)

class Cmp a where
    cmp :: IntPredicate -> Value a -> Value a -> TValue r Bool

instance Cmp Bool where cmp = icmp
instance Cmp Word8 where cmp = icmp
instance Cmp Word16 where cmp = icmp
instance Cmp Word32 where cmp = icmp
instance Cmp Word64 where cmp = icmp
instance Cmp Int8 where cmp = icmp . adjSigned
instance Cmp Int16 where cmp = icmp . adjSigned
instance Cmp Int32 where cmp = icmp . adjSigned
instance Cmp Int64 where cmp = icmp . adjSigned
instance Cmp Float where cmp = fcmp . adjFloat
instance Cmp Double where cmp = fcmp . adjFloat
instance Cmp FP128 where cmp = fcmp . adjFloat

adjSigned :: IntPredicate -> IntPredicate
adjSigned IntUGT = IntSGT
adjSigned IntUGE = IntSGE
adjSigned IntULT = IntSLT
adjSigned IntULE = IntSLE
adjSigned p = p

adjFloat :: IntPredicate -> RealPredicate
adjFloat IntEQ  = RealOEQ
adjFloat IntNE  = RealONE
adjFloat IntUGT = RealOGT
adjFloat IntUGE = RealOGE
adjFloat IntULT = RealOLT
adjFloat IntULE = RealOLE
adjFloat _ = error "adjFloat"

infix  4  %==, %/=, %<, %<=, %>=, %>
(%==), (%/=), (%<), (%<=), (%>), (%>=) :: (Cmp a) => TValue r a -> TValue r a -> TValue r Bool
(%==) = binop $ cmp IntEQ
(%/=) = binop $ cmp IntNE
(%>)  = binop $ cmp IntUGT
(%>=) = binop $ cmp IntUGE
(%<)  = binop $ cmp IntULT
(%<=) = binop $ cmp IntULE

infixr 3  %&&
infixr 2  %||
(%&&) :: TValue r Bool -> TValue r Bool -> TValue r Bool
a %&& b = a ? (b, return (valueOf False))
(%||) :: TValue r Bool -> TValue r Bool -> TValue r Bool
a %|| b = a ? (return (valueOf True), b)

infix  0 ?
(?) :: (IsFirstClass a) => TValue r Bool -> (TValue r a, TValue r a) -> TValue r a
c ? (t, f) = do
    lt <- newBasicBlock
    lf <- newBasicBlock
    lj <- newBasicBlock
    c' <- c
    condBr c' lt lf
    defineBasicBlock lt
    rt <- t
    br lj
    defineBasicBlock lf
    rf <- f
    br lj
    defineBasicBlock lj
    phi [(rt, lt), (rf, lf)]

retrn :: (Ret (Value a) r) => TValue r a -> CodeGenFunction r ()
retrn x = x >>= ret

instance (Show (TValue r a))
instance (Eq (TValue r a))
instance (Ord (TValue r a))

instance (Cmp a, Num a, IsArithmetic a, IsConst a) => Num (TValue r a) where
    (+) = binop add
    (-) = binop sub
    (*) = binop mul
    negate = (>>= neg)
    abs x = x %< 0 ? (-x, x)
    signum x = x %< 0 ? (-1, x %> 0 ? (1, 0))
    fromInteger = return . valueOf . fromInteger

instance (Cmp a, Num a, IsConst a, IsArithmetic a) => Enum (TValue r a) where
    succ x = x + 1
    pred x = x - 1
    fromEnum _ = error "CodeGenFunction Value: fromEnum"
    toEnum = fromIntegral

instance (Cmp a, Num a, IsConst a, IsArithmetic a) => Real (TValue r a) where
    toRational _ = error "CodeGenFunction Value: toRational"

instance (Cmp a, Num a, IsConst a, IsInteger a) => Integral (TValue r a) where
    quot = binop (if (isSigned (undefined :: a)) then sdiv else udiv)
    rem  = binop (if (isSigned (undefined :: a)) then srem else urem)
    quotRem x y = (quot x y, rem x y)
    toInteger _ = error "CodeGenFunction Value: toInteger"

instance (Cmp a, Fractional a, IsConst a, IsFloating a) => Fractional (TValue r a) where
    (/) = binop fdiv
    fromRational = return . valueOf . fromRational

instance (Cmp a, Fractional a, IsConst a, IsFloating a) => RealFrac (TValue r a) where
    properFraction _ = error "CodeGenFunction Value: properFraction"

instance (Cmp a, Floating a, IsConst a, IsFloating a) => Floating (TValue r a) where
    pi = return $ valueOf pi
    sqrt = callIntrinsic1 "sqrt"
    sin = callIntrinsic1 "sin"
    cos = callIntrinsic1 "cos"
    (**) = callIntrinsic2 "pow"
    exp = callIntrinsic1 "exp"
    log = callIntrinsic1 "log"

    asin _ = error "LLVM missing intrinsic: asin"
    acos _ = error "LLVM missing intrinsic: acos"
    atan _ = error "LLVM missing intrinsic: atab"

    sinh x           = (exp x - exp (-x)) / 2
    cosh x           = (exp x + exp (-x)) / 2
    asinh x          = log (x + sqrt (x*x + 1))
    acosh x          = log (x + sqrt (x*x - 1))
    atanh x          = (log (1 + x) - log (1 - x)) / 2

instance (Cmp a, RealFloat a, IsConst a, IsFloating a) => RealFloat (TValue r a) where
    floatRadix _ = floatRadix (undefined :: a)
    floatDigits _ = floatDigits (undefined :: a)
    floatRange _ = floatRange (undefined :: a)
    decodeFloat _ = error "CodeGenFunction Value: decodeFloat"
    encodeFloat _ _ = error "CodeGenFunction Value: encodeFloat"
    exponent _ = 0
    scaleFloat 0 x = x
    scaleFloat _ _ = error "CodeGenFunction Value: scaleFloat"
    isNaN _ = error "CodeGenFunction Value: isNaN"
    isInfinite _ = error "CodeGenFunction Value: isInfinite"
    isDenormalized _ = error "CodeGenFunction Value: isDenormalized"
    isNegativeZero _ = error "CodeGenFunction Value: isNegativeZero"
    isIEEE _ = isIEEE (undefined :: a)

binop :: (Value a -> Value b -> TValue r c) ->
         TValue r a -> TValue r b -> TValue r c
binop op x y = do
    x' <- x
    y' <- y
    op x' y'

callIntrinsic1 :: forall a b r . (IsArithmetic a, IsFirstClass b) =>
	          String -> TValue r a -> TValue r b
callIntrinsic1 fn x = do
    x' <- x
    op <- externFunction ("llvm." ++ fn ++ "." ++ typeName (undefined :: a))
    let _ = op :: Function (a -> IO b)
    call op x'

callIntrinsic2 :: forall a b c r . (IsArithmetic a, IsFirstClass b, IsFirstClass c) =>
	          String -> TValue r a -> TValue r b -> TValue r c
callIntrinsic2 fn x y = do
    x' <- x
    y' <- y
    op <- externFunction ("llvm." ++ fn ++ "." ++ typeName (undefined :: a))
    let _ = op :: Function (a -> b -> IO c)
    call op x' y'

-------------------------------------------

class ArithFunction a b | a -> b, b -> a where
    arithFunction :: a -> b

instance (Ret a r) => ArithFunction (CodeGenFunction r a) (CodeGenFunction r ()) where
    arithFunction x = x >>= ret

instance (ArithFunction b b') => ArithFunction (CodeGenFunction r a -> b) (a -> b') where
    arithFunction f = arithFunction . f . return
