||| This module contains the code for the *micropack*
||| application used for first-time users of Idris2 and
||| pack.
module MicroPack

import Data.Maybe
import Data.SortedMap
import Data.String
import Pack.Config
import Pack.Core
import Pack.Database
import Pack.Runner.Install
import System

%default total

microInit :  (scheme : String)
          -> (db     : DBName)
          ->  Config
microInit scheme db = MkConfig {
    collection    = db
  , scheme        = fromString scheme
  , safetyPrompt  = False
  , withSrc       = True
  , withDocs      = False
  , useKatla      = False
  , withIpkg      = None
  , rlwrap        = False
  , autoLibs      = []
  , autoApps      = []
  , custom        = empty
  , queryType     = NameOnly
  , logLevel      = Info
  , codegen       = Chez
  , output        = "_tmppack"
  }

covering
main : IO ()
main = run $ do
  dir     <- getPackDir
  td      <- mkTmpDir
  mkDir packDir
  defCol  <- defaultColl
  args    <- getArgs
  scheme  <- fromMaybe "scheme" <$> getEnv "SCHEME"

  let db   = case args of
        [_,n] => either (const defCol) id $ readDBName n
        _     => defCol

      conf = microInit scheme db

  -- initialize `$HOME/.pack/user/pack.toml`
  write (MkF (packDir /> "user") packToml) (initToml scheme db)

  finally (rmDir tmpDir) $ idrisEnv >>= update
