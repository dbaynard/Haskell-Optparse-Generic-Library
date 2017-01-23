{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DefaultSignatures          #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeOperators              #-}

-- | This library auto-generates command-line parsers for data types using
-- Haskell's built-in support for generic programming.  The best way to
-- understand how this library works is to walk through a few examples.
--
-- For example, suppose that you want to parse a record with named fields like
-- this:
--
-- > -- Example.hs
-- >
-- > {-# LANGUAGE DeriveGeneric     #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > 
-- > import Options.Generic
-- > 
-- > data Example = Example { foo :: Int, bar :: Double }
-- >     deriving (Generic, Show)
-- > 
-- > instance ParseRecord Example
-- > 
-- > main = do
-- >     x <- getRecord "Test program"
-- >     print (x :: Example)
--
-- Named fields translate to flags which you can provide in any order:
--
-- > $ stack build optparse-generic
-- > $ stack runghc Example.hs -- --bar 2.5 --foo 1
-- > Example {foo = 1, bar = 2.5}
--
-- This also auto-generates @--help@ output:
--
-- > $ stack runghc Example.hs -- --help
-- > Test program
-- > 
-- > Usage: Example.hs --foo INT --bar DOUBLE
-- > 
-- > Available options:
-- >   -h,--help                Show this help text
--
-- You can also add help descriptions to each field, like this:
--
-- > {-# LANGUAGE DataKinds         #-}
-- > {-# LANGUAGE DeriveGeneric     #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > {-# LANGUAGE TypeOperators     #-}
-- > 
-- > import Options.Generic
-- > 
-- > data Example = Example
-- >     { foo :: Int    <?> "Documentation for the foo flag"
-- >     , bar :: Double <?> "Documentation for the bar flag"
-- >     } deriving (Generic, Show)
-- > 
-- > instance ParseRecord Example
-- > 
-- > main = do
-- >     x <- getRecord "Test program"
-- >     print (x :: Example)
--
-- ... which produces the following @--help@ output:
--
-- > $ stack runghc Example.hs -- --help
-- > Test program
-- > 
-- > Usage: Example.hs --foo INT --bar DOUBLE
-- > 
-- > Available options:
-- >   -h,--help                Show this help text
-- >   --foo INT                Documentation for the foo flag
-- >   --bar DOUBLE             Documentation for the bar flag
--
-- However, any fields you document will be wrapped in the `Helpful`
-- constructor:
--
-- > $ stack runghc Example.hs -- --foo 1 --bar 2.5
-- > Example {foo = Helpful {unHelpful = 1}, bar = Helpful {unHelpful = 2.5}}
--
-- For the following examples I encourage you to test what @--help@ output they
-- generate.
--
-- This library will also do the right thing if the fields have no labels:
--
-- > data Example = Example Int Double deriving (Generic, Show)
--
-- Fields without labels translate into positional command-line arguments:
--
-- > $ stack runghc Example.hs -- 1 2.5
-- > Example 1 2.5
--
-- Certain types of fields are given special treatment, such as in this
-- example:
--
-- > data Example = Example
-- >     { switch   :: Bool
-- >     , list     :: [Int]
-- >     , optional :: Maybe   Int
-- >     , first    :: First   Int
-- >     , last     :: Last    Int
-- >     , sum      :: Sum     Int
-- >     , product  :: Product Int
-- >     } deriving (Generic, Show)
--
-- This gives the following behavior:
--
-- > $ stack runghc Example.hs --
-- >       --switch
-- >       --optional 1
-- >       --list    1 --list    2
-- >       --first   1 --first   2
-- >       --last    1 --last    2
-- >       --sum     1 --sum     2
-- >       --product 1 --product 2
-- > Example {switch = True, list = [1,2], optional = Just 1, first = First 
-- > {getFirst = Just 1}, last = Last {getLast = Just 2}, sum = Sum {getSum =
-- > 3}, product = Product {getProduct = 2}}
-- > 
-- > $ stack runghc Example.hs
-- > Example {switch = False, list = [], optional = Nothing, first = First
-- > {getFirst = Nothing}, second = Last {getLast = Nothing}, sum = Sum {getSum
-- > = 0}, product = Product {getProduct = 1}}
--
-- If a datatype has multiple constructors:
--
-- > data Example
-- >     = Create { name :: Text, duration :: Maybe Int }
-- >     | Kill   { name :: Text }
-- >     deriving (Generic, Show)
--
-- ... then they will translate into subcommands named after each constructor:
--
-- > $ stack runghc Example.hs -- create --name foo --duration=60
-- > Create {name = "foo", duration = Just 60}
-- > $ stack runghc Example.hs -- kill --name foo
-- > Kill {name = "foo"}
--
-- This library also provides out-of-the-box support for many existing types,
-- like tuples and `Either`.
--
-- > {-# LANGUAGE DeriveGeneric     #-}
-- > {-# LANGUAGE OverloadedStrings #-}
-- > 
-- > import Options.Generic
-- > 
-- > main = do
-- >     x <- getRecord "Test program"
-- >     print (x :: Either Double Int)
--
-- > $ stack runghc Example.hs -- left 1.0
-- > Left 1.0
-- > $ stack runghc Example.hs -- right 2
-- > Right 2
-- 
-- > main = do
-- >     x <- getRecord "Test program"
-- >     print (x :: (Double, Int))
--
-- > $ stack runghc Example.hs -- 1.0 2
-- > (1.0,2)
--
-- ... and you can also just parse a single value:
--
-- > main = do
-- >     x <- getRecord "Test program"
-- >     print (x :: Int)
--
-- > $ stack runghc Example.hs -- 2
-- > 2
--
-- However, there are some types that this library cannot generate sensible
-- command-line parsers for, such as:
--
-- * recursive types:
--
--     > data Example = Example { foo :: Example }
--
-- * records whose fields are other records
--
--     > data Outer = Outer { foo :: Inner } deriving (Show, Generic)
--     > data Inner = Inner { bar :: Int   } deriving (Show, Generic)
--
-- * record fields  with nested `Maybe`s or nested lists
--
--     > data Example = Example { foo :: Maybe (Maybe Int) }
--     > data Example = Example { foo :: [[Int]]           }
--
-- If you try to auto-generate a parser for these types you will get an error at
-- compile time that will look something like this:
--
-- >     No instance for (ParseFields TheTypeOfYourField)
-- >       arising from a use of ‘Options.Generic.$gdmparseRecord’
-- >     In the expression: Options.Generic.$gdmparseRecord
-- >     In an equation for ‘parseRecord’:
-- >         parseRecord = Options.Generic.$gdmparseRecord
-- >     In the instance declaration for ‘ParseRecord TheTypeOfYourRecord’

module Options.Generic (
    -- * Parsers
      getRecord
    , getRecordPure
    , ParseRecord(..)
    , ParseFields(..)
    , ParseField(..)
    , Only(..)
    , getOnly
    , Modifiers(..)
    , parseRecordWithModifiers
    , defaultModifiers

    -- * Help
    , type (<?>)(..)

    -- * Re-exports
    , Generic
    , Text
    , All(..)
    , Any(..)
    , First(..)
    , Last(..)
    , Sum(..)
    , Product(..)
    ) where

import Control.Applicative
import Control.Monad.IO.Class (MonadIO(..))
import Data.Char (toLower, toUpper)
import Data.Monoid
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.Proxy
import Data.Text (Text)
import Data.Typeable (Typeable)
import Data.Void (Void)
import Filesystem.Path (FilePath)
import GHC.Generics
import Prelude hiding (FilePath)
import Options.Applicative (Parser, ReadM)

import qualified Data.Text
import qualified Data.Text.Encoding
import qualified Data.Text.Lazy
import qualified Data.Text.Lazy.Encoding
import qualified Data.Time.Calendar
import qualified Data.Time.Format
import qualified Data.Typeable
import qualified Data.ByteString
import qualified Data.ByteString.Lazy
import qualified Filesystem.Path.CurrentOS as Filesystem
import qualified Options.Applicative       as Options
import qualified Options.Applicative.Types as Options
import qualified Text.Read

import Data.Tagged (Tagged(..))

#if MIN_VERSION_base(4,7,0)
import GHC.TypeLits
#else
import Data.Singletons.TypeLits
#endif

auto :: Read a => ReadM a
auto = do
    s <- Options.readerAsk
    case Text.Read.readMaybe s of
        Just x  -> return x
        Nothing -> Options.readerAbort Options.ShowHelpText

{-| A class for all record fields that can be parsed from exactly one option or
    argument on the command line

    `parseField` has a default implementation for any type that implements
    `Read` and `Typeable`.  You can derive `Read` for many types and you can
    derive `Typeable` for any type if you enable the @DeriveDataTypeable@
    language extension
-}
class ParseField a where
    parseField
        :: Maybe Text
        -- ^ Help message
        -> Maybe Text
        -- ^ Field label
        -> Parser a
    default parseField
        :: (Typeable a, Read a)
        => Maybe Text
        -- ^ Help message
        -> Maybe Text
        -- ^ Field label
        -> Parser a
    parseField h m = do
        let metavar = map toUpper (show (Data.Typeable.typeOf (undefined :: a)))
        case m of
            Nothing   -> do
                let fs =  Options.metavar metavar
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.argument auto fs
            Just name -> do
                let fs =  Options.metavar metavar
                       <> Options.long (Data.Text.unpack name)
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.option   auto fs

    {-| The only reason for this method is to provide a special case for
        handling `String`s.  All other instances should just fall back on the
        default implementation for `parseListOfField`
    -}
    parseListOfField
        :: Maybe Text
        -- ^ Help message
        -> Maybe Text
        -- ^ Field label
        -> Parser [a]
    parseListOfField h m = many (parseField h m)

instance ParseField Bool
instance ParseField Double
instance ParseField Float
instance ParseField Int
instance ParseField Integer
instance ParseField Ordering
instance ParseField ()
instance ParseField Void

instance ParseField String where
    parseField = parseHelpfulString "STRING"

instance ParseField Char where
    parseField h m = do
        let metavar = "CHAR"
        let readM = do
                s <- Options.readerAsk
                case s of
                    [c] -> return c
                    _   -> Options.readerAbort Options.ShowHelpText
        case m of
            Nothing   -> do
                let fs =  Options.metavar metavar
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.argument readM fs
            Just name -> do
                let fs =  Options.metavar metavar
                       <> Options.long (Data.Text.unpack name)
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.option   readM fs

    parseListOfField = parseHelpfulString "STRING"

instance ParseField Any where
    parseField h m = Any <$> parseField h m
instance ParseField All where
    parseField h m = All <$> parseField h m

parseHelpfulString :: String -> Maybe Text -> Maybe Text -> Parser String
parseHelpfulString metavar h m =
    case m of
        Nothing   -> do
            let fs =  Options.metavar metavar
                   <> maybe mempty (Options.help . Data.Text.unpack) h
            Options.argument Options.str fs
        Just name -> do
            let fs =  Options.metavar metavar
                   <> Options.long (Data.Text.unpack name)
                   <> maybe mempty (Options.help . Data.Text.unpack) h
            Options.option Options.str fs

instance ParseField Data.Text.Text where
    parseField h m = Data.Text.pack <$> parseHelpfulString "TEXT" h m

instance ParseField Data.ByteString.ByteString where
    parseField h m = fmap Data.Text.Encoding.encodeUtf8 (parseField h m)

instance ParseField Data.Text.Lazy.Text where
    parseField h m = Data.Text.Lazy.pack <$> parseHelpfulString "TEXT" h m

instance ParseField Data.ByteString.Lazy.ByteString where
    parseField h m = fmap Data.Text.Lazy.Encoding.encodeUtf8 (parseField h m)

instance ParseField FilePath where
    parseField h m = Filesystem.decodeString <$> parseHelpfulString "FILEPATH" h m

instance ParseField Data.Time.Calendar.Day where
    parseField h m = do
        let metavar = "YYYY-MM-DD"
        case m of
            Nothing   -> do
                let fs =  Options.metavar metavar
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.argument iso8601Day fs
            Just name -> do
                let fs =  Options.metavar metavar
                       <> Options.long (Data.Text.unpack name)
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.option   iso8601Day fs
        where
        iso8601Day = Options.eitherReader
                   $ runReadS . Data.Time.Format.readSTime
                                  False
                                  Data.Time.Format.defaultTimeLocale
                                  "%F"

        runReadS [(day, "")] = Right day
        runReadS _           = Left "expected YYYY-MM-DD"

instance ParseField a => ParseField (Tagged (r :: k) a) where
    parseField h f = Tagged <$> parseField h f

{-| A class for all types that can be parsed from zero or more arguments/options
    on the command line

    `parseFields` has a default implementation for any type that implements
    `ParseField`
-}
class ParseRecord a => ParseFields a where
    parseFields
        :: Maybe Text
        -- ^ Help message
        -> Maybe Text
        -- ^ Field label
        -> Parser a
    default parseFields :: ParseField a => Maybe Text -> Maybe Text -> Parser a
    parseFields = parseField

instance ParseFields Char
instance ParseFields Double
instance ParseFields Float
instance ParseFields Int
instance ParseFields Integer
instance ParseFields Ordering
instance ParseFields Void
instance ParseFields Data.ByteString.ByteString
instance ParseFields Data.ByteString.Lazy.ByteString
instance ParseFields Data.Text.Text
instance ParseFields Data.Text.Lazy.Text
instance ParseFields FilePath
instance ParseFields Data.Time.Calendar.Day

instance ParseFields Bool where
    parseFields h m =
        case m of
            Nothing   -> do
                let fs =  Options.metavar "BOOL"
                       <> maybe mempty (Options.help . Data.Text.unpack) h
                Options.argument auto fs
            Just name -> do
                Options.switch $
                  Options.long (Data.Text.unpack name)
                  <> maybe mempty (Options.help . Data.Text.unpack) h

instance ParseFields () where
    parseFields _ _ = pure ()

instance ParseFields Any where
    parseFields h m = (fmap mconcat . many . fmap Any) (parseField h m)

instance ParseFields All where
    parseFields h m = (fmap mconcat . many . fmap All) (parseField h m)

instance ParseField a => ParseFields (Maybe a) where
    parseFields h m = optional (parseField h m)

instance ParseField a => ParseFields (First a) where
    parseFields h m = (fmap mconcat . many . fmap (First . Just)) (parseField h m)

instance ParseField a => ParseFields (Last a) where
    parseFields h m = (fmap mconcat . many . fmap (Last . Just)) (parseField h m)

instance (Num a, ParseField a) => ParseFields (Sum a) where
    parseFields h m = (fmap mconcat . many . fmap Sum) (parseField h m)

instance (Num a, ParseField a) => ParseFields (Product a) where
    parseFields h m = (fmap mconcat . many . fmap Product) (parseField h m)

instance ParseField a => ParseFields [a] where
    parseFields = parseListOfField

instance ParseField a => ParseFields (NonEmpty a) where
    parseFields h m = (:|) <$> parseField h m <*> parseListOfField h m

instance (ParseField a, ParseFields a) => ParseFields (Tagged (r :: k) a)

{-| Use this to annotate a field with a type-level string (i.e. a `Symbol`)
    representing the help description for that field:

> data Example = Example
>     { foo :: Int    <?> "Documentation for the foo flag"
>     , bar :: Double <?> "Documentation for the bar flag"
>     } deriving (Generic, Show)
-}
newtype (<?>) (field :: *) (help :: Symbol) = Helpful { unHelpful :: field } deriving (Generic, Show)

instance (ParseField a, KnownSymbol h) => ParseField (a <?> h) where
    parseField _ m = Helpful <$>
      parseField ((Just . Data.Text.pack .symbolVal) (Proxy :: Proxy h)) m

instance (ParseFields a, KnownSymbol h) => ParseFields (a <?> h) where
    parseFields _ m = Helpful <$>
      parseFields ((Just . Data.Text.pack .symbolVal) (Proxy :: Proxy h)) m
instance (ParseFields a, KnownSymbol h) => ParseRecord (a <?> h)

{-| A 1-tuple, used solely to translate `ParseFields` instances into
    `ParseRecord` instances
-}
newtype Only a = Only a deriving (Generic, Show)

{-| This is a convenience function that you can use if you want to create a
    `ParseRecord` instance that just defers to the `ParseFields` instance for
    the same type:

> instance ParseRecord MyType where
>     parseRecord = fmap getOnly parseRecord
-}
getOnly :: Only a -> a
getOnly (Only x) = x

{-| A class for types that can be parsed from the command line

    This class has a default implementation for any type that implements
    `Generic` and you can derive `Generic` for many types by enabling the
    @DeriveGeneric@ language extension

    You can also use `getOnly` to create a `ParseRecord` instance from a
    `ParseFields` instance:

> instance ParseRecord MyType where
>     parseRecord = fmap getOnly parseRecord
-}
class ParseRecord a where
    parseRecord :: Parser a
    default parseRecord :: (Generic a, GenericParseRecord (Rep a)) => Parser a
    parseRecord = fmap GHC.Generics.to (genericParseRecord defaultModifiers)

instance ParseFields a => ParseRecord (Only a)

instance ParseRecord Char where
    parseRecord = fmap getOnly parseRecord
instance ParseRecord Double where
    parseRecord = fmap getOnly parseRecord
instance ParseRecord Float where
    parseRecord = fmap getOnly parseRecord
instance ParseRecord Int where
    parseRecord = fmap getOnly parseRecord
instance ParseRecord Ordering
instance ParseRecord Void
instance ParseRecord ()

instance ParseRecord Bool where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Integer where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Data.Text.Text where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Data.Text.Lazy.Text where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Any where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord All where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord FilePath where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Data.ByteString.ByteString where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Data.ByteString.Lazy.ByteString where
    parseRecord = fmap getOnly parseRecord

instance ParseRecord Data.Time.Calendar.Day where
    parseRecord = fmap getOnly parseRecord

instance ParseField a => ParseRecord (Maybe a) where
    parseRecord = fmap getOnly parseRecord

instance ParseField a => ParseRecord (First a) where
    parseRecord = fmap getOnly parseRecord

instance ParseField a => ParseRecord (Last a) where
    parseRecord = fmap getOnly parseRecord

instance (Num a, ParseField a) => ParseRecord (Sum a) where
    parseRecord = fmap getOnly parseRecord

instance (Num a, ParseField a) => ParseRecord (Product a) where
    parseRecord = fmap getOnly parseRecord

instance ParseField a => ParseRecord [a] where
    parseRecord = fmap getOnly parseRecord

instance ParseField a => ParseRecord (NonEmpty a) where
    parseRecord = fmap getOnly parseRecord

instance (ParseField a, ParseFields a) => ParseRecord (Tagged (r :: k) a)

instance (ParseFields a, ParseFields b) => ParseRecord (a, b)
instance (ParseFields a, ParseFields b, ParseFields c) => ParseRecord (a, b, c)
instance (ParseFields a, ParseFields b, ParseFields c, ParseFields d) => ParseRecord (a, b, c, d)
instance (ParseFields a, ParseFields b, ParseFields c, ParseFields d, ParseFields e) => ParseRecord (a, b, c, d, e)
instance (ParseFields a, ParseFields b, ParseFields c, ParseFields d, ParseFields e, ParseFields f) => ParseRecord (a, b, c, d, e, f)
instance (ParseFields a, ParseFields b, ParseFields c, ParseFields d, ParseFields e, ParseFields f, ParseFields g) => ParseRecord (a, b, c, d, e, f, g)

instance (ParseFields a, ParseFields b) => ParseRecord (Either a b)

data Modifiers = Modifiers
  { fieldNameModifier :: String -> String
  , constructorNameModifier :: String -> String
  }

defaultModifiers :: Modifiers
defaultModifiers = Modifiers id (map toLower)

class GenericParseRecord f where
    genericParseRecord :: Modifiers -> Parser (f p)

instance GenericParseRecord U1 where
    genericParseRecord _ = pure U1

-- See: [NOTE - Sums]
instance GenericParseRecord f => GenericParseRecord (M1 C c f) where
    genericParseRecord = fmap M1 . genericParseRecord

-- See: [NOTE - Sums]
instance (GenericParseRecord (f :+: g), GenericParseRecord (h :+: i)) => GenericParseRecord ((f :+: g) :+: (h :+: i)) where
    genericParseRecord mods = do
        fmap L1 (genericParseRecord mods) <|> fmap R1 (genericParseRecord mods)

-- See: [NOTE - Sums]
instance (Constructor c, GenericParseRecord f, GenericParseRecord (g :+: h)) => GenericParseRecord (M1 C c f :+: (g :+: h)) where
    genericParseRecord mods@Modifiers{..} = do
        let m :: M1 i c f a
            m = undefined

        let name = constructorNameModifier (conName m)

        let info = Options.info (Options.helper <*> (genericParseRecord mods)) mempty

        let subparserFields =
                   Options.command name info
                <> Options.metavar name

        let parser = Options.subparser subparserFields

        fmap (L1 . M1) parser <|> fmap R1 (genericParseRecord mods)

-- See: [NOTE - Sums]
instance (Constructor c, GenericParseRecord (f :+: g), GenericParseRecord h) => GenericParseRecord ((f :+: g) :+: M1 C c h) where
    genericParseRecord mods@Modifiers{..} = do
        let m :: M1 i c h a
            m = undefined

        let name = constructorNameModifier (conName m)

        let info = Options.info (Options.helper <*> (genericParseRecord mods)) mempty

        let subparserFields =
                   Options.command name info
                <> Options.metavar name

        let parser = Options.subparser subparserFields

        fmap L1 (genericParseRecord mods) <|> fmap (R1 . M1) parser

-- See: [NOTE - Sums]
instance (Constructor c1, Constructor c2, GenericParseRecord f1, GenericParseRecord f2) => GenericParseRecord (M1 C c1 f1 :+: M1 C c2 f2) where
    genericParseRecord mods@Modifiers{..} = do
        let m1 :: M1 i c1 f a
            m1 = undefined
        let m2 :: M1 i c2 g a
            m2 = undefined

        let name1 = constructorNameModifier (conName m1)
        let name2 = constructorNameModifier (conName m2)

        let info1 = Options.info (Options.helper <*> (genericParseRecord mods)) mempty
        let info2 = Options.info (Options.helper <*> (genericParseRecord mods)) mempty

        let subparserFields1 =
                   Options.command name1 info1
                <> Options.metavar name1
        let subparserFields2 =
                   Options.command name2 info2
                <> Options.metavar name2

        let parser1 = Options.subparser subparserFields1
        let parser2 = Options.subparser subparserFields2

        fmap (L1 . M1) parser1 <|> fmap (R1 . M1) parser2

instance (GenericParseRecord f, GenericParseRecord g) => GenericParseRecord (f :*: g) where
    genericParseRecord mods = liftA2 (:*:) (genericParseRecord mods) (genericParseRecord mods)

instance GenericParseRecord V1 where
    genericParseRecord _ = empty

instance (Selector s, ParseFields a) => GenericParseRecord (M1 S s (K1 i a)) where
    genericParseRecord Modifiers{..} = do
        let m :: M1 i s f a
            m = undefined

        let label = case (selName m) of
                ""   -> Nothing
                name -> Just (Data.Text.pack (fieldNameModifier name))
        fmap (M1 . K1) (parseFields Nothing label)

{- [NOTE - Sums]

   You might wonder why the `GenericParseRecord` instances for `(:+:)` are so
   complicated.  A much simpler approach would be something like this:

> instance (GenericParseRecord f, GenericParseRecord g) => GenericParseRecord (f :+: g) where
>     genericParseRecord = fmap L1 genericParseRecord <|> fmap R1 genericParseRecord
> 
> instance (Constructor c, GenericParseRecord f) => GenericParseRecord (M1 C c f) where
>     genericParseRecord = do
>         let m :: M1 i c f a
>             m = undefined
> 
>         let name = map toLower (conName m)
> 
>         let info = Options.info genericParseRecord mempty
> 
>         let subparserFields =
>                    Options.command n info
>                 <> Options.metavar n
> 
>         fmap M1 (Options.subparser subparserFields)

    The reason for the extra complication is so that datatypes with just one
    constructor don't have subcommands.  That way, if a user defines a data
    type like:

> data Example = Example { foo :: Double } deriving (Generic)
>
> instance ParseRecord Example

    .. then the command line will only read in the @--foo@ flag and won't
    expect a gratuitous @example@ subcommand:

> ./example --foo 2

    However, if a user defines a data type with two constructors then the
    subcommand support will kick in.

    Some other alternatives that I considered and rejected:

    * Alternative #1: Constructors prefixed with something like @Command_@ are
      turned into sub-commands named after the constructor with the prefix
      stripped.  If the prefix is not present then they don't get a subcommand.

        I rejected this approach for several reasons:

        * It's ugly
        * It's error-prone (consider the case: @data T = C1 Int | C2 Int@, which
          would never successfully parse @C2@).  Subcommands should be mandatory
          for types with multiple constructors
        * It doesn't work "out-of-the-box" for most types in the Haskell
          ecosystem which were not written with this library in mind

    * Alternative #2: Any constructor named some reserved name (like @Only@)
      would not generate a sub-command.

        I rejected this approach for a couple of reasons:

        * Too surprising.  The user would never know or guess about this
          behavior without reading the documentation.
        * Doesn't work "out-of-the-box" for single-constructor types in the
          Haskell ecosystem (like `(a, b)`, for example)
-}

instance GenericParseRecord f => GenericParseRecord (M1 D c f) where
    genericParseRecord mods = fmap M1 (Options.helper <*> genericParseRecord mods)

parseRecordWithModifiers :: (Generic a, GenericParseRecord (Rep a)) => Modifiers -> Parser a
parseRecordWithModifiers mods = fmap GHC.Generics.to (genericParseRecord mods)

-- | Marshal any value that implements `ParseRecord` from the command line
getRecord
    :: (MonadIO io, ParseRecord a)
    => Text
    -- ^ Program description
    -> io a
getRecord desc = liftIO (Options.customExecParser prefs info)
  where
    prefs = Options.defaultPrefs
        { Options.prefMultiSuffix = "..."
        }

    header = Options.header (Data.Text.unpack desc)

    info = Options.info parseRecord header

{-| Pure version of `getRecord`

>>> :set -XOverloadedStrings
>>> getRecordPure ["1"] :: Maybe Int
Just 1
>>> getRecordPure ["1", "2"] :: Maybe [Int]
Just [1,2]
>>> getRecordPure ["Foo"] :: Maybe Int
Nothing
-}
getRecordPure
    :: ParseRecord a
    => [Text]
    -- ^ Command-line arguments
    -> Maybe a
getRecordPure args = do
    let prefs = Options.ParserPrefs
            { prefMultiSuffix     = "..."
            , prefDisambiguate    = False
            , prefShowHelpOnError = False
            , prefBacktrack       = True
            , prefColumns         = 80
#if MIN_VERSION_optparse_applicative(0,13,0)
            , prefShowHelpOnEmpty = False
#else
#endif
            }
    let header = Options.header ""
    let info   = Options.info parseRecord header
    let args'  = map Data.Text.unpack args
    Options.getParseResult (Options.execParserPure prefs info args')
