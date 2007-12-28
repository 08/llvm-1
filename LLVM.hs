{-# LANGUAGE TypeSynonymInstances #-}

module LLVM
    (
    -- * Modules
      Module
    , createModule

    -- * Module providers
    , ModuleProvider
    , createModuleProviderForExistingModule

    -- * Types
    , Type
    , addTypeName
    , deleteTypeName
    , getElementType

    -- ** Integer types
    , int1Type
    , int8Type
    , int16Type
    , int32Type
    , int64Type
    , integerType

    -- ** Real types
    , floatType
    , doubleType
    , x86FP80Type
    , fp128Type
    , ppcFP128Type

    -- ** Function types
    , functionType
    , functionTypeVarArgs
    , isFunctionVarArg
    , getReturnType
    , getParamTypes

    -- ** Array, pointer, and vector types
    , pointerType

    -- * Values
    , Value
    , addGlobal
    , setInitializer
    , typeOf

    -- ** Operations on functions
    , addFunction
    , deleteFunction
    , getNamedFunction

    -- * Constants
    , Const(..)

    -- ** Scalar constants
    , constInt
    , constWord
    , constReal

    -- ** Composite constants
    , constString
    , constStringNul

    -- ** Constant expressions
    , constBitCast

    -- * Basic blocks
    , BasicBlock
    , appendBasicBlock
    , insertBasicBlock
    , deleteBasicBlock

    -- * Instruction building
    , Builder
    , createBuilder
    , positionBefore
    , positionAtEnd

    -- ** Memory
    , buildGEP

    -- ** Terminators
    , buildRet

    -- ** Miscellaneous instructions
    , buildCall
    ) where

import Control.Applicative ((<$>))
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Word (Word8, Word16, Word32, Word64)
import Foreign.C.String (withCString, withCStringLen)
import Foreign.Marshal.Array (allocaArray, peekArray, withArrayLen)
import Foreign.Marshal.Utils (fromBool, toBool)
import Foreign.ForeignPtr (ForeignPtr, FinalizerPtr, newForeignPtr,
                           withForeignPtr)
import Foreign.Ptr (Ptr, nullPtr)
import Prelude hiding (mod)
import System.IO.Unsafe (unsafePerformIO)

import qualified LLVM.Base as Base
import LLVM.Internal (Module(..), withModule, ModuleProvider(..), Type(..),
                      Value(..))
import LLVM.Instances ()


createModule :: String -> IO Module
createModule name =
    withCString name $ \namePtr -> do
      ptr <- Base.moduleCreateWithName namePtr
      final <- h2c_module Base.disposeModule
      Module <$> newForeignPtr final ptr

foreign import ccall "wrapper" h2c_module
    :: (Base.ModuleRef -> IO ()) -> IO (FinalizerPtr a)


createModuleProviderForExistingModule :: Module -> IO ModuleProvider
createModuleProviderForExistingModule mod =
    withModule mod $ \modPtr -> do
        ptr <- Base.createModuleProviderForExistingModule modPtr
        final <- h2c_moduleProvider Base.disposeModuleProvider
        ModuleProvider <$> newForeignPtr final ptr

foreign import ccall "wrapper" h2c_moduleProvider
    :: (Base.ModuleProviderRef -> IO ()) -> IO (FinalizerPtr a)


addTypeName :: Module -> Type -> String -> IO Bool
addTypeName mod typ name =
    withModule mod $ \modPtr ->
      withCString name $ \namePtr ->
        (/=0) <$> Base.addTypeName modPtr namePtr (fromType typ)
                 
deleteTypeName :: Module -> String -> IO ()
deleteTypeName mod name =
    withModule mod $ \modPtr ->
      withCString name $ Base.deleteTypeName modPtr

getElementType :: Type -> Type
getElementType = Type . Base.getElementType . fromType

int1Type :: Type
int1Type = Type Base.int1Type

int8Type :: Type
int8Type = Type Base.int8Type

int16Type :: Type
int16Type = Type Base.int16Type

int32Type :: Type
int32Type = Type Base.int32Type

int64Type :: Type
int64Type = Type Base.int64Type

integerType :: Int -> Type
integerType = Type . Base.integerType . fromIntegral

floatType :: Type
floatType = Type Base.floatType

doubleType :: Type
doubleType = Type Base.doubleType

x86FP80Type :: Type
x86FP80Type = Type Base.x86FP80Type

fp128Type :: Type
fp128Type = Type Base.fp128Type

ppcFP128Type :: Type
ppcFP128Type = Type Base.ppcFP128Type

functionTypeInternal :: Type -> [Type] -> Bool -> Type
functionTypeInternal retType paramTypes varargs = unsafePerformIO $
    withArrayLen (map fromType paramTypes) $ \len ptr ->
        return . Type $ Base.functionType (fromType retType) ptr
                        (fromIntegral len) (fromBool varargs)

functionType :: Type -> [Type] -> Type
functionType retType paramTypes =
    functionTypeInternal retType paramTypes False

functionTypeVarArgs :: Type -> [Type] -> Type
functionTypeVarArgs retType paramTypes =
    functionTypeInternal retType paramTypes True

isFunctionVarArg :: Type -> Bool
isFunctionVarArg = toBool . Base.isFunctionVarArg . fromType

getReturnType :: Type -> Type
getReturnType = Type . Base.getReturnType . fromType

getParamTypes :: Type -> [Type]
getParamTypes typ = unsafePerformIO $ do
    let typ' = fromType typ
        count = Base.countParamTypes typ'
        len = fromIntegral count
    allocaArray len $ \ptr -> do
      Base.getParamTypes typ' ptr
      map Type <$> peekArray len ptr

pointerType :: Type -> Type
pointerType typ = Type $ Base.pointerType (fromType typ) 0


addGlobal :: Module -> Type -> String -> IO Value
addGlobal mod typ name =
    withModule mod $ \modPtr ->
      withCString name $ \namePtr ->
        Value <$> Base.addGlobal modPtr (fromType typ) namePtr

setInitializer :: Value -> Value -> IO ()
setInitializer global cnst =
    Base.setInitializer (fromValue global) (fromValue cnst)

typeOf :: Value -> Type
typeOf val = unsafePerformIO $ Type <$> Base.typeOf (fromValue val)

addFunction :: Module -> String -> Type -> IO Value
addFunction mod name typ =
    withModule mod $ \modPtr ->
      withCString name $ \namePtr ->
        Value <$> Base.addFunction modPtr namePtr (fromType typ)

deleteFunction :: Value -> IO ()
deleteFunction = Base.deleteFunction . fromValue

maybePtr :: (Ptr a -> b) -> Ptr a -> Maybe b
maybePtr f ptr | ptr /= nullPtr = Just (f ptr)
               | otherwise = Nothing

getNamedFunction :: Module -> String -> IO (Maybe Value)
getNamedFunction mod name =
    withModule mod $ \modPtr ->
      withCString name $ \namePtr ->
        maybePtr Value <$> Base.getNamedFunction modPtr namePtr

constWord :: Type -> Word64 -> Value
constWord typ val = Value $ Base.constInt (fromType typ) (fromIntegral val) 0

constInt :: Type -> Int64 -> Value
constInt typ val = Value $ Base.constInt (fromType typ) (fromIntegral val) 1

constReal :: Type -> Double -> Value
constReal typ val = Value $ Base.constReal (fromType typ) (realToFrac val)

constString :: String -> Value
constString s = unsafePerformIO $
    withCStringLen s $ \(sPtr, sLen) ->
      return . Value $ Base.constString sPtr (fromIntegral sLen) 1

constStringNul :: String -> Value
constStringNul s = unsafePerformIO $
    withCStringLen s $ \(sPtr, sLen) ->
      return . Value $ Base.constString sPtr (fromIntegral sLen) 0

constBitCast :: Type -> Value -> Value
constBitCast typ val = Value $ Base.constBitCast (fromValue val) (fromType typ)

class Const a where
    const :: a -> Value

instance Const String where
    const = constStringNul

instance Const Float where
    const = constReal floatType . fromRational . toRational

instance Const Double where
    const = constReal doubleType

instance Const Int8 where
    const = constInt int8Type . fromIntegral

instance Const Int16 where
    const = constInt int16Type . fromIntegral

instance Const Int32 where
    const = constInt int32Type . fromIntegral

instance Const Int64 where
    const = constInt int64Type

instance Const Word8 where
    const = constWord int8Type . fromIntegral

instance Const Word16 where
    const = constWord int16Type . fromIntegral

instance Const Word32 where
    const = constWord int32Type . fromIntegral

instance Const Word64 where
    const = constWord int64Type


newtype BasicBlock = BasicBlock {fromBasicBlock :: Base.BasicBlockRef}

appendBasicBlock :: Value -> String -> IO BasicBlock
appendBasicBlock func name =
    withCString name $ \namePtr ->
      BasicBlock <$> Base.appendBasicBlock (fromValue func) namePtr

insertBasicBlock :: BasicBlock -> String -> IO BasicBlock
insertBasicBlock before name =
    withCString name $ \namePtr ->
      BasicBlock <$> Base.insertBasicBlock (fromBasicBlock before) namePtr

deleteBasicBlock :: BasicBlock -> IO ()
deleteBasicBlock = Base.deleteBasicBlock . fromBasicBlock


newtype Builder = Builder {fromBuilder :: ForeignPtr Base.Builder}

withBuilder :: Builder -> (Base.BuilderRef -> IO a) -> IO a
withBuilder bld = withForeignPtr (fromBuilder bld)

createBuilder :: IO Builder
createBuilder = do
  final <- h2c_builder Base.disposeBuilder
  ptr <- Base.createBuilder
  Builder <$> newForeignPtr final ptr

foreign import ccall "wrapper" h2c_builder
    :: (Base.BuilderRef -> IO ()) -> IO (FinalizerPtr a)

positionBefore :: Builder -> Value -> IO ()
positionBefore bld insn =
    withBuilder bld $ \bldPtr ->
      Base.positionBefore bldPtr (fromValue insn)

positionAtEnd :: Builder -> BasicBlock -> IO ()
positionAtEnd bld bblk =
    withBuilder bld $ \bldPtr ->
      Base.positionAtEnd bldPtr (fromBasicBlock bblk)

buildGEP :: Builder -> Value -> [Value] -> String -> IO Value
buildGEP bld ptr indices name =
    withBuilder bld $ \bldPtr ->
      withCString name $ \namePtr ->
        withArrayLen (map fromValue indices) $ \idxLen idxPtr ->
          Value <$> Base.buildGEP bldPtr (fromValue ptr) idxPtr
                                  (fromIntegral idxLen) namePtr

buildRet :: Builder -> Value -> IO Value
buildRet bld val =
    withBuilder bld $ \bldPtr ->
      Value <$> Base.buildRet bldPtr (fromValue val)

buildCall :: Builder -> Value -> [Value] -> String -> IO Value
buildCall bld func args name =
    withBuilder bld $ \bldPtr ->
      withArrayLen (map fromValue args) $ \argLen argPtr ->
        withCString name $ \namePtr ->
          Value <$> Base.buildCall bldPtr (fromValue func) argPtr
                                   (fromIntegral argLen) namePtr
