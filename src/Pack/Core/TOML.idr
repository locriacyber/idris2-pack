module Pack.Core.TOML

import Data.SortedMap as M
import Idris.Package.Types
import public Language.TOML
import Pack.Core.IO
import Pack.Core.Types

%default total

--------------------------------------------------------------------------------
--          Interface
--------------------------------------------------------------------------------

||| Interface for using a pack data type as a key
||| in a TOML table.
public export
interface Ord a => TOMLKey a where
  ||| Tries to convert a key to a value of type `a`
  fromKey : (k : String) -> Either TOMLErr a

export
TOMLKey DBName where
  fromKey s = case Body.parse s of
    Just b  => Right $ MkDBName b
    Nothing => Left $ WrongType [] "collection name"

export
TOMLKey PkgName where fromKey = Right . MkPkgName

||| Interface for converting a TOML value to a pack
||| data type. We pass the TOML file's absolute path
||| as an additional argument, since this allows us to
||| convert relative paths listed in the TOML file
||| (for instance, the path to a local package) to absolute ones.
public export
interface FromTOML a where
  ||| Tries to convert a `Value` to a value of type `a`.
  fromTOML : File Abs -> (val  : Value) -> Either TOMLErr a

--------------------------------------------------------------------------------
--          Utilities
--------------------------------------------------------------------------------

||| Read a value of type `b` by reading a value of
||| type `a` and converting it with the given function.
export
tmap : FromTOML a => (a -> b) -> File Abs -> Value -> Either TOMLErr b
tmap f p = map f . fromTOML p

||| Read a value of type `b` by refining a value of
||| type `a`.
export
trefine :  FromTOML a
        => (a -> Either TOMLErr b)
        -> File Abs
        -> Value
        -> Either TOMLErr b
trefine f p v = fromTOML p v >>= f

||| Try to extract a value from a toml `Value`.
|||
||| @ get   : Tries to convert the value found at the given `path` to a values of
|||           the result type.
||| @ path  : Dot-separated path to the value we'd like to read.
||| @ deflt : Optional default value to use if there is not entry
|||           at the given `path`. Note: This will not be used if there
|||           is an entry at `path`. In this case, the value found will
|||           always be handed over to `get`, resulting in a failure if
|||           it can't be properly converted.
||| @ value : The TOML value we start with.
export
valAt' :  (get  : Value -> Either TOMLErr a)
       -> (path : String)
       -> (dflt : Maybe a)
       -> (val  : Value)
       -> Either TOMLErr a
valAt' get path dflt = go (forget $ split ('.' ==) path)
  where go : List String -> Value -> Either TOMLErr a
        go []        v          = get v
        go (x :: xs) (VTable y) = case lookup x y of
          Nothing => case dflt of
            Nothing => Left $ MissingKey [x]
            Just a  => Right a
          Just v2 => prefixKey x $ go xs v2
        go _ _                  = Left $ WrongType [] "Table"

||| Extract and convert a mandatory value from a TOML
||| value. The `path` string can contain several dot-separated
||| key names. See also `valAt'`.
export %inline
valAt :  FromTOML a
      => (path : String)
      -> File Abs
      -> (val : Value)
      -> Either TOMLErr a
valAt path f = valAt' (fromTOML f) path Nothing

||| Extract and convert an optional value from a TOML
||| value. The `path` string can contain several dot-separated
||| key names. See also `valAt'`.
export %inline
optValAt :  FromTOML a
         => (path : String)
         -> File Abs
         -> (dflt : a)
         -> (val  : Value)
         -> Either TOMLErr a
optValAt path f = valAt' (fromTOML f) path . Just

||| Extract and convert an optional value from a TOML
||| value. The `path` string can contain several dot-separated
||| key names. See also `valAt'`.
export
maybeValAt' :  (f    : Value -> Either TOMLErr a)
            -> (path : String)
            -> (val  : Value)
            -> Either TOMLErr (Maybe a)
maybeValAt' f path = valAt' (map Just . f) path (Just Nothing)

||| Extract and convert an optional value from a TOML
||| value. The `path` string can contain several dot-separated
||| key names. See also `valAt'`.
export %inline
maybeValAt :  FromTOML a
           => (path : String)
           -> File Abs
           -> (val  : Value)
           -> Either TOMLErr (Maybe a)
maybeValAt p f = maybeValAt' (fromTOML f) p

--------------------------------------------------------------------------------
--          Implementations
--------------------------------------------------------------------------------

export
FromTOML String where
  fromTOML _ (VString s) = Right s
  fromTOML _ _           = Left $ WrongType [] "String"

export
FromTOML PkgName where fromTOML = tmap MkPkgName

export
FromTOML URL where fromTOML = tmap MkURL

export
FromTOML Commit where fromTOML = tmap MkCommit

export
FromTOML FilePath where fromTOML = tmap fromString

toRelPath : FilePath -> Either TOMLErr (Path Rel)
toRelPath (FP $ PRel sx) = Right (PRel sx)
toRelPath (FP $ PAbs _)  = Left (WrongType [] "Relative Path")

toRelFile : FilePath -> Either TOMLErr (File Rel)
toRelFile (FP $ PRel (sx :< x)) = Right (MkF (PRel sx) x)
toRelFile _                     = Left (WrongType [] "relative file path")

export %inline
FromTOML (Path Rel) where fromTOML = trefine toRelPath

export %inline
FromTOML (File Rel) where fromTOML = trefine toRelFile

export %inline
FromTOML DBName where fromTOML = trefine fromKey

export
FromTOML Bool where
  fromTOML _ (VBoolean b) = Right b
  fromTOML _ _            = Left $ WrongType [] "Bool"

export
FromTOML a => FromTOML (List a) where
  fromTOML f (VArray vs) = traverse (fromTOML f) vs
  fromTOML _ _           = Left $ WrongType [] "Array"

readVersion : String -> Either TOMLErr PkgVersion
readVersion s = case traverse parsePositive $ split ('.' ==) s of
  Just ns => Right $ MkPkgVersion ns
  Nothing => Left $ WrongType [] "Package Version"

export
FromTOML PkgVersion where
  fromTOML = trefine readVersion

keyVal :  TOMLKey k
       => (Value -> Either TOMLErr v)
       -> (String,Value)
       -> Either TOMLErr (k,v)
keyVal f (x,y) = prefixKey x [| MkPair (fromKey x) (f y) |]

-- -- TODO: Remove this.
-- -- export
-- -- sortedMap :  TOMLKey k
-- --           => (Path Abs -> Value -> Either TOMLErr v)
-- --           -> Path Abs
-- --           -> Value
-- --           -> Either TOMLErr (SortedMap k v)
-- -- sortedMap f dir (VTable m) =
-- --   M.fromList <$> traverse (keyVal $ f dir) (M.toList m)
-- -- sortedMap _ _    _         = Left $ WrongType [] "Table"

export
TOMLKey k => FromTOML v => FromTOML (SortedMap k v) where
  fromTOML f (VTable m) =
    M.fromList <$> traverse (keyVal $ fromTOML f) (M.toList m)
  fromTOML _ _          = Left $ WrongType [] "Table"

export
FromTOML (Path Abs) where
  fromTOML f v = toAbsPath f.parent <$> fromTOML f v

export
FromTOML (File Abs) where
  fromTOML f v = toAbsFile f.parent <$> fromTOML f v

-- -- ||| Read an absolute path from a .toml file that could also be given
-- -- ||| as a path relative to the .toml file's parent directory. We therefore
-- -- ||| need the parent directory as an additional input.
-- -- export
-- -- absPathAt :  (path : String)
-- --           -> (dir  : Path Abs) -- parent directory of the .toml file we read
-- --           -> (val  : Value)
-- --           -> Either TOMLErr (Path Abs)
-- -- absPathAt path dir val = toAbsPath dir <$> valAt path val
--
-- -- ||| Read an absolute file path from a .toml file that could also be given
-- -- ||| as a path relative to the .toml file's parent directory. We therefore
-- -- ||| need the parent directory as an additional input.
-- -- export
-- -- absFileAt :  (path : String)
-- --           -> (dir  : Path Abs) -- parent directory of the .toml file we read
-- --           -> (val  : Value)
-- --           -> Either TOMLErr (File Abs)
-- -- absFileAt path dir val = toAbsFile dir <$> valAt path val
--
--------------------------------------------------------------------------------
--          Reading a TOML File
--------------------------------------------------------------------------------

||| Reads a file and converts its content to a TOML value.
export covering
readTOML :  HasIO io => File Abs -> EitherT PackErr io Value
readTOML file = do
  str <- read file
  case parseTOML str of
    Right v  => pure (VTable v)
    Left err => throwE $ TOMLParse file (show err)

||| Reads a file, converts its content to a TOML value, and
||| extracts an Idris value from this.
export covering
readFromTOML :  HasIO io
             => (0 a : Type)
             -> FromTOML a
             => File Abs
             -> EitherT PackErr io a
readFromTOML _ file = do
  v <- readTOML file
  liftEither $ mapFst (TOMLFile file) (fromTOML file v)

||| Reads a file, converts its content to a TOML value, and
||| extracts an Idris value from this.
export covering
readOptionalFromTOML :  HasIO io
                     => (0 a : Type)
                     -> FromTOML a
                     => File Abs
                     -> EitherT PackErr io a
readOptionalFromTOML a f = do
  True <- fileExists f
    | False => liftEither (mapFst (TOMLFile f) $ fromTOML f (VTable empty))
  readFromTOML a f
