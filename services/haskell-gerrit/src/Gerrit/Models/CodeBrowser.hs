{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.CodeBrowser
    ( -- * Types
      FileView(..)
    , FileHistory(..)
    , BlameInfo(..)
    , SyntaxConfig(..)
    , ViewContext(..)
    , HighlightRange(..)
      -- * Operations
    , createFileView
    , getFileHistory
    , getBlameInfo
    , getHighlightedContent
    , migrateAll
    ) where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Hashable (hash)
import Control.Monad (void)
import Database.Persist.Sql

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)
import Gerrit.Models.Revision (Revision)

-- | View context for file browsing
data ViewContext
    = ChangeContext ChangeId RevisionId  -- ^ Viewing in context of a change
    | BranchContext Text Text            -- ^ Viewing in context of a branch (repo, branch)
    | CommitContext Text                 -- ^ Viewing at a specific commit
    deriving (Show, Eq, Generic)

instance ToJSON ViewContext
instance FromJSON ViewContext

derivePersistField "ViewContext"

-- | Syntax highlighting range
data HighlightRange = HighlightRange
    { startLine :: Int
    , endLine :: Int
    , startColumn :: Int
    , endColumn :: Int
    , tokenType :: Text      -- ^ Type of token (keyword, string, comment, etc.)
    , tokenClass :: Text     -- ^ CSS class for styling
    } deriving (Show, Eq, Generic)

instance ToJSON HighlightRange
instance FromJSON HighlightRange

derivePersistField "HighlightRange"

-- | Syntax highlighting configuration
data SyntaxConfig = SyntaxConfig
    { language :: Text                -- ^ Programming language
    , theme :: Text                  -- ^ Color theme
    , lineNumbers :: Bool            -- ^ Show line numbers
    , highlightLines :: [Int]        -- ^ Lines to highlight
    , foldRanges :: [(Int, Int)]     -- ^ Line ranges that can be folded
    , customRules :: Value           -- ^ Language-specific rules
    } deriving (Show, Eq, Generic)

instance ToJSON SyntaxConfig
instance FromJSON SyntaxConfig

derivePersistField "SyntaxConfig"

-- | File view entity
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
FileView
    viewId Text
    context ViewContext
    filePath Text
    content Text
    syntaxConfig SyntaxConfig
    highlights [HighlightRange]
    metadata Value Maybe
    created UTCTime
    UniqueViewId viewId
    deriving Show Eq Generic

FileHistory
    historyId Text
    filePath Text
    commitId Text
    authorId Text
    message Text
    diff Text
    timestamp UTCTime
    metadata Value Maybe
    UniqueHistoryId historyId
    deriving Show Eq Generic

BlameInfo
    blameId Text
    filePath Text
    lineNumber Int
    commitId Text
    authorId Text
    timestamp UTCTime
    content Text
    metadata Value Maybe
    UniqueBlameLineId blameId filePath lineNumber
    deriving Show Eq Generic

SyntaxCache
    cacheId Text
    filePath Text
    language Text
    content Text
    highlightedContent Text
    ranges [HighlightRange]
    timestamp UTCTime
    UniqueCacheId cacheId
    deriving Show Eq Generic
|]

instance ToJSON (Entity FileView)
instance ToJSON FileView
instance FromJSON FileView

instance ToJSON (Entity FileHistory)
instance ToJSON FileHistory
instance FromJSON FileHistory

instance ToJSON (Entity BlameInfo)
instance ToJSON BlameInfo
instance FromJSON BlameInfo

instance ToJSON (Entity SyntaxCache)
instance ToJSON SyntaxCache
instance FromJSON SyntaxCache

-- | Create a new file view
createFileView :: MonadIO m
               => ConnectionPool
               -> ViewContext
               -> Text  -- ^ File path
               -> Text  -- ^ Content
               -> SyntaxConfig  -- ^ Syntax configuration
               -> [HighlightRange]  -- ^ Highlight ranges
               -> m (Entity FileView)
createFileView pool context' path' content' config' highlights' = do
    now <- liftIO getCurrentTime
    let viewId' = generateViewId context' path' now
    let view = FileView
            { fileViewViewId = viewId'
            , fileViewContext = context'
            , fileViewFilePath = path'
            , fileViewContent = content'
            , fileViewSyntaxConfig = config'
            , fileViewHighlights = highlights'
            , fileViewMetadata = Nothing
            , fileViewCreated = now
            }
    runSqlPool (insertEntity view) pool

-- | Get file history
getFileHistory :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ File path
               -> Int   -- ^ Limit
               -> Int   -- ^ Offset
               -> m [Entity FileHistory]
getFileHistory pool path' limit offset =
    runSqlPool (selectList [FileHistoryFilePath ==. path']
                          [Desc FileHistoryTimestamp, LimitTo limit, OffsetBy offset]) pool

-- | Get blame information for a file
getBlameInfo :: MonadIO m
             => ConnectionPool
             -> Text  -- ^ File path
             -> m [Entity BlameInfo]
getBlameInfo pool path' =
    runSqlPool (selectList [BlameInfoFilePath ==. path']
                          [Asc BlameInfoLineNumber]) pool

-- | Get highlighted content from cache or generate new
getHighlightedContent :: MonadIO m
                     => ConnectionPool
                     -> Text  -- ^ File path
                     -> Text  -- ^ Content
                     -> Text  -- ^ Language
                     -> m (Text, [HighlightRange])  -- ^ (Highlighted content, ranges)
getHighlightedContent pool path content lang = do
    -- Try to get from cache first
    let cacheId = generateCacheId path content lang
    mCached <- runSqlPool (getBy $ UniqueCacheId cacheId) pool
    case mCached of
        -- Return cached content if found and content matches
        Just (Entity _ cache) | syntaxCacheContent cache == content ->
            return (syntaxCacheHighlightedContent cache, syntaxCacheRanges cache)

        -- Generate new highlighted content
        _ -> do
            (highlighted, ranges) <- generateHighlightedContent content lang
            now <- liftIO getCurrentTime

            -- Store in cache
            let cache = SyntaxCache
                    { syntaxCacheCacheId = cacheId
                    , syntaxCacheFilePath = path
                    , syntaxCacheLanguage = lang
                    , syntaxCacheContent = content
                    , syntaxCacheHighlightedContent = highlighted
                    , syntaxCacheRanges = ranges
                    , syntaxCacheTimestamp = now
                    }
            void $ runSqlPool (insertBy cache) pool

            return (highlighted, ranges)

-- | Generate a unique cache ID
generateCacheId :: Text -> Text -> Text -> Text
generateCacheId path content lang =
    "cache-" <> hashText (path <> content <> lang)
  where
    hashText = Text.pack . show . hash . Text.unpack

-- | Generate syntax highlighted content
generateHighlightedContent :: MonadIO m
                         => Text  -- ^ Content to highlight
                         -> Text  -- ^ Language
                         -> m (Text, [HighlightRange])  -- ^ (Highlighted content, ranges)
generateHighlightedContent content lang = do
    let lines = Text.lines content
    let tokens = concatMap (tokenizeLine lang) (zip [1..] lines)
    let (highlighted, ranges) = processTokens tokens
    return (highlighted, ranges)

-- | Process tokens into highlighted content and ranges
processTokens :: [(Int, Text, TokenType)] -> (Text, [HighlightRange])
processTokens tokens = (highlighted, ranges)
  where
    highlighted = Text.concat
        [ Text.concat
            [ "<span class=\"syntax-" <> tokenTypeClass tokType <> "\">"
            , escapeHtml content
            , "</span>"
            ]
        | (_, content, tokType) <- tokens
        ]

    ranges = [ HighlightRange
                { startLine = line
                , endLine = line
                , startColumn = 1
                , endColumn = Text.length content
                , tokenType = tokenTypeText tokType
                , tokenClass = "syntax-" <> tokenTypeText tokType
                }
            | (line, content, tokType) <- tokens
            ]

-- | Helper to escape HTML special characters
escapeHtml :: Text -> Text
escapeHtml = Text.concatMap escape
  where
    escape '<' = "&lt;"
    escape '>' = "&gt;"
    escape '&' = "&amp;"
    escape '"' = "&quot;"
    escape '\'' = "&#39;"
    escape c = Text.singleton c

-- | Token types for syntax highlighting
data TokenType
    = Keyword
    | Identifier
    | String
    | Number
    | Comment
    | Operator
    | Delimiter
    | Other
    deriving (Show, Eq)

tokenTypeText :: TokenType -> Text
tokenTypeText = Text.pack . show

tokenTypeClass :: TokenType -> Text
tokenTypeClass = Text.toLower . tokenTypeText

-- | Basic tokenization of a line
tokenizeLine :: Text -> (Int, Text) -> [(Int, Text, TokenType)]
tokenizeLine lang (lineNum, line) =
    let tokens = Text.words line
        classify word
            | isKeyword lang word = Keyword
            | isOperator lang word = Operator
            | isString word = String
            | isNumber word = Number
            | otherwise = Identifier
    in [(lineNum, token, classify token) | token <- tokens]

-- | Check if a word is a keyword in the given language
isKeyword :: Text -> Text -> Bool
isKeyword lang word =
    case lang of
        "haskell" -> word `Set.member` haskellKeywords
        _ -> False

-- | Check if a word is an operator
isOperator :: Text -> Text -> Bool
isOperator lang word =
    case lang of
        "haskell" -> word `Set.member` haskellOperators
        _ -> False

-- | Check if a word is a string literal
isString :: Text -> Bool
isString text =
    (Text.head text == '"' && Text.last text == '"') ||
    (Text.head text == '\'' && Text.last text == '\'')

-- | Check if a word is a number
isNumber :: Text -> Bool
isNumber = Text.all (\c -> c `elem` (['0'..'9'] ++ ['.', '-', '+']))

-- | Haskell keywords
haskellKeywords :: Set.Set Text
haskellKeywords = Set.fromList
    [ "module", "where", "import", "data", "type", "newtype"
    , "class", "instance", "deriving", "do", "case", "of"
    , "let", "in", "if", "then", "else", "forall"
    ]

-- | Haskell operators
haskellOperators :: Set.Set Text
haskellOperators = Set.fromList
    [ "->", "<-", "=>", "::", "=", "|", "\\", "@", "~", ".."
    , "$", "<$>", "<*>", ">>=", ">>", "<<", "++", "+", "-"
    ]

-- Types for syntax highlighting implementation
data SyntaxHighlighter = SyntaxHighlighter
    { shLanguage :: Text
    , shDefinition :: LanguageDefinition
    , shOptions :: HighlightOptions
    }

data LanguageDefinition = LanguageDefinition
    { ldKeywords :: Set Text
    , ldOperators :: Set Text
    , ldCommentStart :: Maybe Text
    , ldCommentEnd :: Maybe Text
    , ldStringDelimiters :: Set Text
    , ldCustomRules :: [CustomRule]
    }

data HighlightOptions = HighlightOptions
    { hoLineNumbers :: Bool
    , hoTheme :: Text
    , hoTabSize :: Int
    }

data Token = Token
    { tokenType :: Text
    , tokenContent :: Text
    , tokenLine :: Int
    , tokenStartCol :: Int
    , tokenEndCol :: Int
    }

defaultHighlightOptions :: HighlightOptions
defaultHighlightOptions = HighlightOptions
    { hoLineNumbers = True
    , hoTheme = "default"
    , hoTabSize = 4
    }

-- | Load language definition from built-in rules or custom configuration
loadLanguageDefinition :: MonadIO m => Text -> m LanguageDefinition
loadLanguageDefinition lang = do
    -- Load built-in language definition or custom rules
    case Map.lookup lang builtinLanguages of
        Just def -> return def
        Nothing -> loadCustomLanguageDefinition lang

-- | Built-in language definitions
builtinLanguages :: Map Text LanguageDefinition
builtinLanguages = Map.fromList
    [ ("haskell", haskellDefinition)
    , ("python", pythonDefinition)
    , ("javascript", javascriptDefinition)
    , ("typescript", typescriptDefinition)
    , ("java", javaDefinition)
    , ("c", cDefinition)
    , ("cpp", cppDefinition)
    , ("rust", rustDefinition)
    , ("go", goDefinition)
    ]

-- | Example language definition for Haskell
haskellDefinition :: LanguageDefinition
haskellDefinition = LanguageDefinition
    { ldKeywords = Set.fromList
        [ "module", "where", "import", "data", "type", "newtype"
        , "class", "instance", "deriving", "do", "case", "of"
        , "let", "in", "if", "then", "else", "forall"
        ]
    , ldOperators = Set.fromList
        [ "->", "<-", "=>", "::", "=", "|", "\\", "@", "~", ".."
        , "$", "<$>", "<*>", ">>=", ">>", "<<", "++", "+", "-"
        ]
    , ldCommentStart = Just "{-"
    , ldCommentEnd = Just "-}"
    , ldStringDelimiters = Set.fromList ["\"", "'"]
    , ldCustomRules = []
    }

-- | Helper function to generate a unique view ID
generateViewId :: ViewContext -> Text -> UTCTime -> Text
generateViewId context path timestamp =
    "V" <> Text.filter isAllowed (contextStr <> "-" <> path <> "-" <> showt timestamp)
  where
    showt = Text.pack . show
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])
    contextStr = case context of
        ChangeContext cid rid -> "change-" <> cid <> "-" <> rid
        BranchContext repo branch -> "branch-" <> repo <> "-" <> branch
        CommitContext commit -> "commit-" <> commit
