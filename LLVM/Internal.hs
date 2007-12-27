module LLVM.Internal
    (
      Module(..)
    , withModule
    , ModuleProvider(..)
    , withModuleProvider
    , Type(..)
    ) where

import Foreign.ForeignPtr (ForeignPtr, withForeignPtr)
import Foreign.Ptr (Ptr)

import qualified LLVM.Base as Base


newtype Module = Module {fromModule :: ForeignPtr Base.Module}

withModule :: Module -> (Ptr Base.Module -> IO a) -> IO a
withModule mod = withForeignPtr (fromModule mod)

newtype ModuleProvider = ModuleProvider {
      fromModuleProvider :: ForeignPtr Base.ModuleProvider
    }

withModuleProvider :: ModuleProvider -> (Ptr Base.ModuleProvider -> IO a)
                   -> IO a
withModuleProvider prov = withForeignPtr (fromModuleProvider prov)

newtype Type = Type {fromType :: Ptr Base.Type}
                          
