{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.CodeBrowserService
    ( -- * Types
      CodeBrowserService(..)
    , FileInfo(..)
    , DiffInfo(..)
    , HighlightOptions(..)
    , HighlightRange(..)
    , TokenType(..)
    , FoldRegion(..)
    , FoldType(..)
    , WordDiff(..)
    , DiffOperation(..)
    , SyntaxState(..)
    , WordDiffType
    , EnhancedWordDiff
      -- * Service creation
    , createCodeBrowserService
    , listFiles
    , getFile
    , getRawFile
    , getFileHistory
    , getBlameInfo
    , getHighlightedFile
    , updateHighlighting
    , searchFiles
    , getFileDiff
    , addFileComment
    , getFileComments
    , listLanguages
    , listThemes
    , addCustomSyntaxRules
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist.Sql
import qualified Database.Persist.Sql as Sql
import qualified Data.Map as M
import System.Process (readProcess)
import Control.Exception (SomeException)
import Data.List (foldl')

import Gerrit.Models.Types
import Gerrit.Models.CodeBrowser
import Gerrit.Models.Repository (Repository)
import Gerrit.Models.Comment (Comment)
import Gerrit.Utils.Error (ServiceError(..))

-- | Code browser service
data CodeBrowserService = CodeBrowserService
    { codePool :: ConnectionPool
    , codeConfig :: Value
    }

-- | File information
data FileInfo = FileInfo
    { filePath :: Text
    , fileName :: Text
    , fileSize :: Integer
    , mimeType :: Text
    , lastModified :: UTCTime
    , metadata :: Value
    }

-- | Diff information
data DiffInfo = DiffInfo
    { diOldPath :: Text
    , diNewPath :: Text
    , diOldContent :: Text
    , diNewContent :: Text
    , diHunks :: [DiffHunk]
    , diStats :: DiffStats
    }

-- | Diff hunk information
data DiffHunk = DiffHunk
    { dhOldStart :: Int
    , dhOldCount :: Int
    , dhNewStart :: Int
    , dhNewCount :: Int
    , dhLines :: [(DiffLineType, Text)]
    }

-- | Diff line type
data DiffLineType = Context | Added | Removed
    deriving (Show, Eq)

-- | Diff statistics
data DiffStats = DiffStats
    { dsAdded :: Int
    , dsRemoved :: Int
    , dsChanged :: Int
    }

-- | Highlight options
data HighlightOptions = HighlightOptions
    { hoLanguage :: Text
    , hoTheme :: Text
    , hoLineNumbers :: Bool
    , hoTabSize :: Int
    , hoCustomRules :: Maybe Value
    } deriving (Show, Eq)

-- | Highlight range
data HighlightRange = HighlightRange
    { hrStartLine :: Int
    , hrStartCol :: Int
    , hrEndLine :: Int
    , hrEndCol :: Int
    , hrTokenType :: Text
    , hrTokenClass :: Text
    } deriving (Show, Eq)

-- | Token type for syntax highlighting
data TokenType
    = Keyword
    | Identifier
    | String
    | Number
    | Comment
    | Operator
    | Punctuation
    | Whitespace
    | Other Text
    deriving (Show, Eq)

-- | Fold region for code folding
data FoldRegion = FoldRegion
    { frStartLine :: Int
    , frEndLine :: Int
    , frType :: FoldType
    } deriving (Show, Eq)

-- | Fold type for code folding
data FoldType
    = ImportsFold
    | FunctionFold
    | ClassFold
    | CommentFold
    | BraceFold
    deriving (Show, Eq)

-- | Enhanced word-level diff with semantic understanding
data WordDiffType
    = TextDiff      -- ^ Regular text difference
    | IdentifierDiff  -- ^ Variable/function name change
    | LiteralDiff     -- ^ String/number literal change
    | KeywordDiff     -- ^ Language keyword change
    | WhitespaceDiff  -- ^ Whitespace/formatting change
    deriving (Show, Eq)

-- | Enhanced word diff with semantic information
data EnhancedWordDiff = EnhancedWordDiff
    { ewdOldWords :: [Text]
    , ewdNewWords :: [Text]
    , ewdOperations :: [(DiffOperation, Int, WordDiffType)]
    } deriving (Show, Eq)

-- | Word-level diff information
data WordDiff = WordDiff
    { wdOldWords :: [Text]
    , wdNewWords :: [Text]
    , wdOperations :: [(DiffOperation, Int)]
    } deriving (Show, Eq)

-- | Diff operation for word-level diff
data DiffOperation
    = KeepWord
    | InsertWord
    | DeleteWord
    deriving (Show, Eq)

-- | Real-time syntax highlighting support
data SyntaxState = SyntaxState
    { ssInComment :: Bool
    , ssInString :: Bool
    , ssStringDelimiter :: Maybe Char
    , ssIndentLevel :: Int
    , ssLanguage :: Text
    } deriving (Show, Eq)

-- | Create a new code browser service
createCodeBrowserService :: MonadIO m => ConnectionPool -> Value -> m CodeBrowserService
createCodeBrowserService pool config = pure $ CodeBrowserService
    { codePool = pool
    , codeConfig = config
    }

-- | List files in a repository
listFiles :: MonadIO m
         => CodeBrowserService
         -> Text  -- ^ Repository ID
         -> Maybe Text  -- ^ Path prefix
         -> m [FileInfo]
listFiles service repoId mPrefix = runSqlPool action (codePool service)
  where
    action = do
        let filters = (FileViewRepoId ==. repoId) :
                     maybe [] (\prefix -> [FileViewFilePath `like` (prefix <> "%")]) mPrefix
        views <- selectList filters [Asc FileViewFilePath]
        return $ map (fileInfoFromView . entityVal) views

-- | Get file content with metadata
getFile :: MonadIO m
        => CodeBrowserService
        -> Text  -- ^ Repository ID
        -> Text  -- ^ File path
        -> m (Maybe FileInfo)
getFile service repoId path = runSqlPool action (codePool service)
  where
    action = do
        mView <- getBy $ UniqueFileView repoId path
        return $ fileInfoFromView . entityVal <$> mView

-- | Get raw file content
getRawFile :: MonadIO m
           => CodeBrowserService
           -> Text  -- ^ Repository ID
           -> Text  -- ^ File path
           -> m (Maybe Text)
getRawFile service repoId path = runSqlPool action (codePool service)
  where
    action = do
        mView <- getBy $ UniqueFileView repoId path
        return $ fileViewContent . entityVal <$> mView

-- | Get file history
getFileHistory :: MonadIO m
               => CodeBrowserService
               -> Text  -- ^ Repository ID
               -> Text  -- ^ File path
               -> Maybe UTCTime  -- ^ Start time
               -> Maybe UTCTime  -- ^ End time
               -> m [FileHistory]
getFileHistory service repoId path mStart mEnd = runSqlPool action (codePool service)
  where
    action = do
        let filters = [FileHistoryFilePath ==. path] ++
                     maybe [] (\start -> [FileHistoryTimestamp >=. start]) mStart ++
                     maybe [] (\end -> [FileHistoryTimestamp <=. end]) mEnd
        selectList filters [Desc FileHistoryTimestamp]

-- | Get blame information for a file
getBlameInfo :: MonadIO m
             => CodeBrowserService
             -> Text  -- ^ Repository ID
             -> Text  -- ^ File path
             -> m [BlameInfo]
getBlameInfo service repoId path = runSqlPool action (codePool service)
  where
    action = selectList [BlameInfoFilePath ==. path] [Asc BlameInfoLineNumber]

-- | Initialize syntax state for a language
initSyntaxState :: Text -> SyntaxState
initSyntaxState lang = SyntaxState
    { ssInComment = False
    , ssInString = False
    , ssStringDelimiter = Nothing
    , ssIndentLevel = 0
    , ssLanguage = lang
    }

-- | Incrementally highlight a line of code
highlightLine :: SyntaxState -> Text -> (Text, [HighlightRange], SyntaxState)
highlightLine state line =
    let (tokens, newState) = tokenizeLine state line
        (highlighted, ranges) = processTokens tokens 1 1 []
    in (highlighted, ranges, newState)

-- | Tokenize a line of code with state
tokenizeLine :: SyntaxState -> Text -> ([(TokenType, Text)], SyntaxState)
tokenizeLine state@SyntaxState{..} line =
    let (tokens, newState) = go state (T.unpack line) [] ""
    in (reverse tokens, newState)
  where
    go state [] acc current
        | not (null current) =
            let token = classifyToken (languageKeywords ssLanguage)
                                    (languageOperators ssLanguage)
                                    (T.pack current)
            in (token : acc, state)
        | otherwise = (acc, state)

    go state@SyntaxState{..} (c:cs) acc current
        | ssInComment = case blockCommentEnd (languageCommentMarkers ssLanguage) of
            end | T.pack (c : take (T.length end - 1) cs) == end ->
                go state{ssInComment = False}
                   (drop (T.length end - 1) cs)
                   ((Comment, T.pack (current ++ c : take (T.length end - 1) cs)) : acc)
                   ""
            _ -> go state cs acc (current ++ [c])

        | ssInString = case c of
            c' | Just c' == ssStringDelimiter ->
                go state{ssInString = False, ssStringDelimiter = Nothing}
                   cs
                   ((String, T.pack (current ++ [c])) : acc)
                   ""
            '\\' | not (null cs) ->
                go state (tail cs) acc (current ++ ['\\', head cs])
            _ -> go state cs acc (current ++ [c])

        | c `elem` ['\"', '\''] =
            let token = if not (null current)
                       then classifyToken (languageKeywords ssLanguage)
                                        (languageOperators ssLanguage)
                                        (T.pack current)
                       else []
            in go state{ssInString = True, ssStringDelimiter = Just c}
                  cs
                  (token ++ acc)
                  [c]

        | isCommentStart state (c : take 1 cs) =
            let token = if not (null current)
                       then classifyToken (languageKeywords ssLanguage)
                                        (languageOperators ssLanguage)
                                        (T.pack current)
                       else []
            in go state{ssInComment = True}
                  (drop 1 cs)
                  (token ++ acc)
                  [c]

        | isSpace c =
            let token = if not (null current)
                       then classifyToken (languageKeywords ssLanguage)
                                        (languageOperators ssLanguage)
                                        (T.pack current)
                       else []
            in go state cs (token ++ acc) ""

        | isPunctuation c =
            let token = if not (null current)
                       then classifyToken (languageKeywords ssLanguage)
                                        (languageOperators ssLanguage)
                                        (T.pack current)
                       else []
                punctToken = [(Punctuation, T.singleton c)]
            in go state cs (punctToken ++ token ++ acc) ""

        | otherwise = go state cs acc (current ++ [c])

    isCommentStart state chars =
        let start = blockCommentStart (languageCommentMarkers ssLanguage)
        in T.pack (take (T.length start) chars) == start

-- | Enhanced getHighlightedFile with real-time support
getHighlightedFile :: MonadIO m
                   => CodeBrowserService
                   -> Text  -- ^ Repository ID
                   -> Text  -- ^ File path
                   -> Text  -- ^ Commit ID
                   -> HighlightOptions  -- ^ Highlighting options
                   -> m (Either Text (Text, [HighlightRange], [FoldRegion], SyntaxState))
getHighlightedFile service repoId filePath commitId options = do
    result <- getFileContent service repoId filePath commitId
    case result of
        Left err -> return $ Left err
        Right content -> do
            let initialState = initSyntaxState (hoLanguage options)
                lines = T.lines content
                (highlighted, ranges, finalState) =
                    foldl' processLine ([], [], initialState) lines
                foldRegions = detectFoldRegions content (hoLanguage options)
            return $ Right (T.unlines highlighted, concat ranges, foldRegions, finalState)
  where
    processLine (acc, ranges, state) line =
        let (highlighted, newRanges, newState) = highlightLine state line
        in (highlighted : acc, newRanges : ranges, newState)

-- | Get raw file content from repository
getFileContent :: MonadIO m
               => CodeBrowserService
               -> Text  -- ^ Repository ID
               -> Text  -- ^ File path
               -> Text  -- ^ Commit ID
               -> m (Either Text Text)
getFileContent service repoId filePath commitId = runSqlPool action (codePool service)
  where
    action = do
        -- First check if we have the content cached in file_views
        mView <- getBy $ UniqueFileView repoId filePath
        case mView of
            Just (Entity _ view) -> do
                -- Check if the cached content is for the requested commit
                let metadata = fileViewMetadata view
                case metadata .:? "commitId" of
                    Just (String cachedCommit) | cachedCommit == commitId ->
                        return $ Right $ fileViewContent view
                    _ -> retrieveFromRepo
            Nothing -> retrieveFromRepo

    retrieveFromRepo = do
        -- Get repository information
        mRepo <- get repoId
        case mRepo of
            Nothing -> return $ Left "Repository not found"
            Just repo -> do
                -- Execute git command to get file content
                let cmd = "git -C " <> repoPath repo <> " show " <> commitId <> ":" <> filePath
                result <- liftIO $ try $ readProcess "sh" ["-c", T.unpack cmd] ""
                case result of
                    Left (e :: SomeException) ->
                        return $ Left $ "Error reading file: " <> T.pack (show e)
                    Right content -> do
                        -- Cache the content
                        now <- liftIO getCurrentTime
                        void $ insertBy $ FileView
                            { fileViewRepoId = repoId
                            , fileViewFilePath = filePath
                            , fileViewContent = T.pack content
                            , fileViewSyntaxConfig = Nothing
                            , fileViewMetadata = object
                                [ "commitId" .= commitId
                                , "cachedAt" .= now
                                ]
                            , fileViewCreated = now
                            }
                        return $ Right $ T.pack content

-- | Update syntax highlighting configuration
updateHighlighting :: MonadIO m
                   => CodeBrowserService
                   -> Text  -- ^ Repository ID
                   -> Text  -- ^ File path
                   -> Value  -- ^ New configuration
                   -> m Bool
updateHighlighting service repoId path config = runSqlPool action (codePool service)
  where
    action = do
        mView <- getBy $ UniqueFileView repoId path
        case mView of
            Nothing -> return False
            Just (Entity key view) -> do
                update key [FileViewSyntaxConfig =. config]
                -- Invalidate cache
                deleteWhere [SyntaxCacheFilePath ==. path]
                return True

-- | Search files in a repository
searchFiles :: MonadIO m
            => CodeBrowserService
            -> Text  -- ^ Repository ID
            -> Text  -- ^ Search query
            -> Value  -- ^ Search options
            -> m [SearchResult]
searchFiles service repoId query options = runSqlPool action (codePool service)
  where
    action = do
        -- Record search query
        now <- liftIO getCurrentTime
        _ <- insert $ SearchQuery
            { searchQueryQueryId = generateQueryId repoId query now
            , searchQueryUserId = "system"  -- TODO: Get from context
            , searchQueryQuery = query
            , searchQueryFilters = Just options
            , searchQueryResultCount = 0  -- Will be updated
            , searchQueryExecutionTime = 0  -- Will be updated
            , searchQueryTimestamp = now
            }
        -- Perform search
        results <- rawSql
            "SELECT * FROM search_results \
            \WHERE index_id IN (SELECT index_id FROM code_search_indices WHERE repo_id = ?) \
            \AND text_search_vector @@ plainto_tsquery('english', ?) \
            \ORDER BY ts_rank(text_search_vector, plainto_tsquery('english', ?)) DESC \
            \LIMIT 100"
            [PersistText repoId, PersistText query, PersistText query]
        return results

-- | Get file diff with enhanced features
getFileDiff :: MonadIO m
            => CodeBrowserService
            -> Text  -- ^ Repository ID
            -> Text  -- ^ File path
            -> Text  -- ^ Old commit ID
            -> Text  -- ^ New commit ID
            -> m (Either Text (DiffInfo, [EnhancedWordDiff]))
getFileDiff service repoId filePath oldCommit newCommit = do
    oldContent <- getFileContent service repoId filePath oldCommit
    newContent <- getFileContent service repoId filePath newCommit
    case (oldContent, newContent) of
        (Right old, Right new) -> do
            let diff = computeLineDiff old new
                wordDiffs = zipWith computeEnhancedWordDiff
                    (T.lines old)
                    (T.lines new)
            return $ Right (diff, wordDiffs)
        (Left err, _) -> return $ Left $ "Error reading old version: " <> err
        (_, Left err) -> return $ Left $ "Error reading new version: " <> err

-- | Convert diff hunk to DiffHunk type
convertHunk :: (Int, Int, Int, Int, [(DiffLineType, Text)]) -> DiffHunk
convertHunk (oldStart, oldCount, newStart, newCount, lines) =
    DiffHunk
        { dhOldStart = oldStart
        , dhOldCount = oldCount
        , dhNewStart = newStart
        , dhNewCount = newCount
        , dhLines = lines
        }

-- | Calculate diff statistics
calculateDiffStats :: [(Int, Int, Int, Int, [(DiffLineType, Text)])] -> DiffStats
calculateDiffStats hunks =
    let allLines = concatMap (\(_, _, _, _, lines) -> lines) hunks
        added = length $ filter ((== Added) . fst) allLines
        removed = length $ filter ((== Removed) . fst) allLines
        changed = max added removed
    in DiffStats
        { dsAdded = added
        , dsRemoved = removed
        , dsChanged = changed
        }

-- | Add file comment
addFileComment :: MonadIO m
               => CodeBrowserService
               -> Text  -- ^ Repository ID
               -> Text  -- ^ File path
               -> Int   -- ^ Line number
               -> Text  -- ^ Comment text
               -> m ()
addFileComment service repoId path line comment = runSqlPool action (codePool service)
  where
    action = do
        now <- liftIO getCurrentTime
        -- Create comment
        let commentId = generateCommentId repoId path line now
        _ <- insert $ Comment
            { commentCommentId = commentId
            , commentRepoId = repoId
            , commentFilePath = path
            , commentLineNumber = line
            , commentText = comment
            , commentAuthorId = "system"  -- TODO: Get from context
            , commentCreated = now
            , commentUpdated = now
            , commentMetadata = Nothing
            }
        -- Update file view metadata
        mView <- getBy $ UniqueFileView repoId path
        case mView of
            Just (Entity key view) -> do
                let commentCount = maybe 0 ((+ 1) . fromMaybe 0 . (.:? "commentCount")) $ fileViewMetadata view
                    newMetadata = object
                        [ "commentCount" .= commentCount
                        , "lastCommentAt" .= now
                        ]
                update key [FileViewMetadata =. newMetadata]
            Nothing -> return ()

-- | Get file comments
getFileComments :: MonadIO m
                => CodeBrowserService
                -> Text  -- ^ Repository ID
                -> Text  -- ^ File path
                -> m [Comment]
getFileComments service repoId path = runSqlPool action (codePool service)
  where
    action = do
        comments <- selectList
            [ CommentRepoId ==. repoId
            , CommentFilePath ==. path
            ]
            [Asc CommentLineNumber, Asc CommentCreated]
        return $ map entityVal comments

-- | List supported languages
listLanguages :: MonadIO m
              => CodeBrowserService
              -> m [Text]
listLanguages service = return
    [ "haskell", "rust", "c", "cpp", "javascript", "typescript"
    , "python", "java", "go", "ruby", "php", "html", "css"
    , "markdown", "yaml", "json", "sql", "shell", "dockerfile"
    , "scala", "kotlin", "swift", "r", "matlab", "perl"
    , "lua", "elixir", "erlang", "clojure", "ocaml", "f#"
    ]

-- | List available themes
listThemes :: MonadIO m
           => CodeBrowserService
           -> m [Text]
listThemes service = return
    [ "default", "dark", "light", "monokai", "solarized-dark"
    , "solarized-light", "github", "vscode", "dracula"
    ]

-- | Add custom syntax rules
addCustomSyntaxRules :: MonadIO m
                    => CodeBrowserService
                    -> Text  -- ^ Language
                    -> Value  -- ^ Rules
                    -> m ()
addCustomSyntaxRules service lang rules = runSqlPool action (codePool service)
  where
    action = do
        now <- liftIO getCurrentTime
        let ruleId = generateRuleId lang now
        _ <- insertUnique $ SyntaxRule
            { syntaxRuleRuleId = ruleId
            , syntaxRuleLanguage = lang
            , syntaxRulePattern = rules
            , syntaxRuleCreated = now
            }
        -- Invalidate cache for this language
        deleteWhere [SyntaxCacheLanguage ==. lang]

-- Helper functions

fileInfoFromView :: FileView -> FileInfo
fileInfoFromView view = FileInfo
    { filePath = fileViewFilePath view
    , fileName = T.takeWhileEnd (/= '/') $ fileViewFilePath view
    , fileSize = T.length $ fileViewContent view
    , mimeType = determineMimeType $ fileViewFilePath view
    , lastModified = fileViewCreated view
    , metadata = fileViewMetadata view
    }

-- | Language-specific keywords
languageKeywords :: Text -> [Text]
languageKeywords lang = case T.toLower lang of
    "haskell" ->
        [ "module", "where", "import", "data", "type", "newtype", "class"
        , "instance", "deriving", "do", "let", "in", "case", "of", "if"
        , "then", "else", "qualified", "as", "hiding"
        ]
    "rust" ->
        [ "fn", "let", "mut", "pub", "use", "mod", "struct", "enum"
        , "impl", "trait", "type", "const", "static", "if", "else"
        , "match", "loop", "while", "for", "in", "continue", "break"
        ]
    "python" ->
        [ "def", "class", "import", "from", "as", "if", "elif", "else"
        , "try", "except", "finally", "raise", "with", "for", "while"
        , "in", "is", "not", "and", "or", "return", "yield", "lambda"
        , "async", "await", "pass", "break", "continue", "global"
        ]
    "javascript" ->
        [ "function", "const", "let", "var", "if", "else", "for", "while"
        , "do", "switch", "case", "break", "continue", "return", "try"
        , "catch", "finally", "throw", "class", "extends", "new", "this"
        , "super", "import", "export", "default", "null", "undefined"
        , "async", "await", "yield", "typeof", "instanceof", "in"
        ]
    "typescript" ->
        [ "interface", "type", "enum", "implements", "declare", "namespace"
        , "abstract", "private", "protected", "public", "readonly", "static"
        ] ++ languageKeywords "javascript"
    "go" ->
        [ "func", "package", "import", "type", "struct", "interface"
        , "const", "var", "if", "else", "switch", "case", "default"
        , "for", "range", "break", "continue", "return", "go", "defer"
        , "select", "chan", "map", "fallthrough", "goto"
        ]
    "java" ->
        [ "class", "interface", "enum", "extends", "implements", "package"
        , "import", "public", "private", "protected", "static", "final"
        , "abstract", "synchronized", "volatile", "transient", "native"
        , "strictfp", "throws", "throw", "try", "catch", "finally"
        , "if", "else", "for", "while", "do", "switch", "case", "break"
        , "continue", "return", "new", "instanceof", "super", "this"
        ]
    _ -> []

-- | Language-specific operators
languageOperators :: Text -> [Text]
languageOperators lang = case T.toLower lang of
    "haskell" ->
        [ "->", "<-", "=>", "::", "=", "|", "\\", "@", "~", "$"
        , ".", "+", "-", "*", "/", "<", ">", "<=", ">=", "=="
        ]
    "rust" ->
        [ "=", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*"
        , "/", "%", "&&", "||", "!", "&", "|", "^", "<<", ">>"
        ]
    "python" ->
        [ "+", "-", "*", "/", "//", "%", "**", "==", "!=", "<"
        , ">", "<=", ">=", "=", "+=", "-=", "*=", "/=", "//="
        , "%=", "**=", "&=", "|=", "^=", ">>=", "<<="
        ]
    "javascript" | "typescript" ->
        [ "=", "==", "===", "!=", "!==", "<", ">", "<=", ">="
        , "+", "-", "*", "/", "%", "**", "++", "--", "&&", "||"
        , "!", "&", "|", "^", "~", "<<", ">>", ">>>", "??"
        , "?..", "?.", "+=", "-=", "*=", "/=", "%=", "**="
        ]
    "go" ->
        [ "=", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*"
        , "/", "%", "&&", "||", "!", "&", "|", "^", "<<", ">>"
        , "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<="
        , ">>=", "&^", "&^=", "<-", ":="
        ]
    "java" ->
        [ "=", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*"
        , "/", "%", "&&", "||", "!", "&", "|", "^", "~", "<<"
        , ">>", ">>>", "+=", "-=", "*=", "/=", "%=", "&=", "|="
        , "^=", "<<=", ">>=", ">>>="
        ]
    _ -> []

-- | Detect foldable regions in code
detectFoldRegions :: Text -> Text -> [FoldRegion]
detectFoldRegions content lang =
    let lines = T.lines content
        importFolds = detectImportFolds lines lang
        functionFolds = detectFunctionFolds lines lang
        classFolds = detectClassFolds lines lang
        commentFolds = detectCommentFolds lines lang
        braceFolds = detectBraceFolds lines
    in importFolds ++ functionFolds ++ classFolds ++ commentFolds ++ braceFolds

-- | Detect import statement blocks
detectImportFolds :: [Text] -> Text -> [FoldRegion]
detectImportFolds lines lang =
    let isImport = case T.toLower lang of
            "haskell" -> \l -> "import" `T.isPrefixOf` T.stripStart l
            "python" -> \l -> "import " `T.isPrefixOf` T.stripStart l || "from " `T.isPrefixOf` T.stripStart l
            "javascript" | "typescript" -> \l -> "import " `T.isPrefixOf` T.stripStart l
            "java" | "go" -> \l -> "import " `T.isPrefixOf` T.stripStart l
            _ -> const False

        go [] _ _ acc = reverse acc
        go (l:ls) lineNum start acc
            | isImport l && start == 0 = go ls (lineNum + 1) lineNum acc
            | isImport l = go ls (lineNum + 1) start acc
            | start > 0 = go ls (lineNum + 1) 0
                (FoldRegion start (lineNum - 1) ImportsFold : acc)
            | otherwise = go ls (lineNum + 1) 0 acc
    in go lines 1 0 []

-- | Detect function definitions
detectFunctionFolds :: [Text] -> Text -> [FoldRegion]
detectFunctionFolds lines lang =
    let isFunction = case T.toLower lang of
            "haskell" -> \l -> not (T.null l) && not ("import" `T.isPrefixOf` T.stripStart l) && "::" `T.isInfixOf` l
            "python" -> \l -> "def " `T.isPrefixOf` T.stripStart l
            "javascript" | "typescript" -> \l -> "function " `T.isPrefixOf` T.stripStart l || "=> {" `T.isPrefixOf` l
            "go" -> \l -> "func " `T.isPrefixOf` T.stripStart l
            "java" -> \l -> any (`T.isInfixOf` l) ["public ", "private ", "protected "] && "(" `T.isInfixOf` l
            _ -> const False

        go [] _ _ acc = reverse acc
        go (l:ls) lineNum start acc
            | isFunction l && start == 0 = go ls (lineNum + 1) lineNum acc
            | start > 0 && T.stripStart l == T.empty =
                go ls (lineNum + 1) 0 (FoldRegion start (lineNum - 1) FunctionFold : acc)
            | otherwise = go ls (lineNum + 1) start acc
    in go lines 1 0 []

-- | Detect class definitions
detectClassFolds :: [Text] -> Text -> [FoldRegion]
detectClassFolds lines lang =
    let isClass = case T.toLower lang of
            "haskell" -> \l -> "class " `T.isPrefixOf` T.stripStart l
            "python" -> \l -> "class " `T.isPrefixOf` T.stripStart l
            "javascript" | "typescript" -> \l -> "class " `T.isPrefixOf` T.stripStart l
            "java" -> \l -> "class " `T.isPrefixOf` T.stripStart l || "interface " `T.isPrefixOf` T.stripStart l
            _ -> const False

        go [] _ _ acc = reverse acc
        go (l:ls) lineNum start acc
            | isClass l && start == 0 = go ls (lineNum + 1) lineNum acc
            | start > 0 && T.stripStart l == T.empty =
                go ls (lineNum + 1) 0 (FoldRegion start (lineNum - 1) ClassFold : acc)
            | otherwise = go ls (lineNum + 1) start acc
    in go lines 1 0 []

-- | Detect comment blocks
detectCommentFolds :: [Text] -> Text -> [FoldRegion]
detectCommentFolds lines lang =
    let markers = languageCommentMarkers lang
        isCommentStart = \l -> T.stripStart l `T.isPrefixOf` blockCommentStart markers
        isCommentEnd = \l -> T.stripStart l `T.isPrefixOf` blockCommentEnd markers

        go [] _ _ acc = reverse acc
        go (l:ls) lineNum start acc
            | isCommentStart l && start == 0 = go ls (lineNum + 1) lineNum acc
            | isCommentEnd l && start > 0 =
                go ls (lineNum + 1) 0 (FoldRegion start lineNum CommentFold : acc)
            | otherwise = go ls (lineNum + 1) start acc
    in go lines 1 0 []

-- | Detect brace-based fold regions
detectBraceFolds :: [Text] -> [FoldRegion]
detectBraceFolds lines =
    let go [] _ stack acc = reverse acc
        go (l:ls) lineNum stack acc =
            let opens = T.count "{" l
                closes = T.count "}" l
                newStack = updateStack stack opens closes
                newRegions = if closes > 0
                            then createRegions stack lineNum closes
                            else []
            in go ls (lineNum + 1) newStack (newRegions ++ acc)

        updateStack stack opens closes =
            let stack' = stack ++ replicate opens lineNum
            in drop closes stack'

        createRegions stack lineNum closes =
            let starts = reverse $ take closes stack
            in [FoldRegion start lineNum BraceFold | start <- starts]
    in go lines 1 [] []

-- | Compute enhanced word-level diff
computeEnhancedWordDiff :: Text -> Text -> EnhancedWordDiff
computeEnhancedWordDiff oldText newText =
    let oldWords = T.words oldText
        newWords = T.words newText
        operations = computeEnhancedWordEditScript oldWords newWords
    in EnhancedWordDiff
        { ewdOldWords = oldWords
        , ewdNewWords = newWords
        , ewdOperations = operations
        }

-- | Compute edit script with semantic information
computeEnhancedWordEditScript :: [Text] -> [Text] -> [(DiffOperation, Int, WordDiffType)]
computeEnhancedWordEditScript old new =
    let baseScript = computeWordEditScript old new
        withTypes = map addDiffType baseScript
    in withTypes
  where
    addDiffType (op, idx) = (op, idx, classifyDiffType op idx old new)

-- | Classify the type of difference
classifyDiffType :: DiffOperation -> Int -> [Text] -> [Text] -> WordDiffType
classifyDiffType op idx old new = case op of
    KeepWord -> TextDiff
    InsertWord | isIdentifier (new !! idx) -> IdentifierDiff
    InsertWord | isLiteral (new !! idx) -> LiteralDiff
    InsertWord | isKeyword (new !! idx) -> KeywordDiff
    InsertWord | isWhitespace (new !! idx) -> WhitespaceDiff
    InsertWord -> TextDiff
    DeleteWord | isIdentifier (old !! idx) -> IdentifierDiff
    DeleteWord | isLiteral (old !! idx) -> LiteralDiff
    DeleteWord | isKeyword (old !! idx) -> KeywordDiff
    DeleteWord | isWhitespace (old !! idx) -> WhitespaceDiff
    DeleteWord -> TextDiff

-- | Helper functions for diff type classification
isIdentifier :: Text -> Bool
isIdentifier text = case T.uncons text of
    Nothing -> False
    Just (c, rest) -> isValidIdentStart c && T.all isValidIdentChar rest
  where
    isValidIdentStart c = c == '_' || isAlpha c
    isValidIdentChar c = c == '_' || isAlphaNum c

isLiteral :: Text -> Bool
isLiteral text =
    isStringLiteral text || isNumberLiteral text

isNumberLiteral :: Text -> Bool
isNumberLiteral text =
    case T.uncons text of
        Nothing -> False
        Just (c, rest) ->
            (isDigit c || (c == '-' && not (T.null rest))) &&
            T.all (\c -> isDigit c || c `elem` ['.','-','e','E','+']) rest

isKeyword :: Text -> Bool
isKeyword text = text `elem` allKeywords

isWhitespace :: Text -> Bool
isWhitespace = T.all isSpace

-- | Combined list of keywords from all supported languages
allKeywords :: [Text]
allKeywords = concat
    [ languageKeywords "haskell"
    , languageKeywords "rust"
    , languageKeywords "python"
    , languageKeywords "javascript"
    , languageKeywords "typescript"
    , languageKeywords "go"
    , languageKeywords "java"
    ]

-- | Convert token type to text representation
tokenTypeToText :: TokenType -> Text
tokenTypeToText = \case
    Keyword -> "keyword"
    Identifier -> "identifier"
    String -> "string"
    Number -> "number"
    Comment -> "comment"
    Operator -> "operator"
    Punctuation -> "punctuation"
    Whitespace -> "whitespace"
    Method -> "method"
    Type -> "type"
    FormatString -> "format-string"
    Other t -> t

-- | Convert token type to CSS class
tokenTypeToClass :: TokenType -> Text
tokenTypeToClass = \case
    Keyword -> "hljs-keyword"
    Identifier -> "hljs-identifier"
    String -> "hljs-string"
    Number -> "hljs-number"
    Comment -> "hljs-comment"
    Operator -> "hljs-operator"
    Punctuation -> "hljs-punctuation"
    Whitespace -> ""
    Method -> "hljs-method"
    Type -> "hljs-type"
    FormatString -> "hljs-format-string"
    Other _ -> ""

-- | Repository path helper
repoPath :: Repository -> Text
repoPath repo = "/var/lib/gerrit/repos/" <> repositoryName repo  -- Adjust path as needed

generateCacheId :: Text -> Text -> Text
generateCacheId path language = "cache_" <> T.filter isAllowed path <> "_" <> language
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateQueryId :: Text -> Text -> UTCTime -> Text
generateQueryId repoId query timestamp =
    "q_" <> T.filter isAllowed repoId <> "_" <> T.filter isAllowed query <> "_" <> T.pack (show timestamp)
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

determineMimeType :: Text -> Text
determineMimeType path = case T.toLower $ T.takeWhileEnd (/= '.') path of
    "hs"     -> "text/x-haskell"
    "rs"     -> "text/x-rust"
    "c"      -> "text/x-c"
    "cpp"    -> "text/x-c++"
    "h"      -> "text/x-c"
    "hpp"    -> "text/x-c++"
    "js"     -> "text/javascript"
    "ts"     -> "text/typescript"
    "json"   -> "application/json"
    "yaml"   -> "text/yaml"
    "yml"    -> "text/yaml"
    "md"     -> "text/markdown"
    "txt"    -> "text/plain"
    _        -> "application/octet-stream"

generateCommentId :: Text -> Text -> Int -> UTCTime -> Text
generateCommentId repoId path line timestamp =
    "c_" <> T.filter isAllowed repoId <> "_" <> T.filter isAllowed path <>
    "_" <> T.pack (show line) <> "_" <> T.pack (show timestamp)
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

generateRuleId :: Text -> UTCTime -> Text
generateRuleId lang timestamp =
    "r_" <> T.filter isAllowed lang <> "_" <> T.pack (show timestamp)
  where
    isAllowed c = c `elem` (['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ ['_', '-'])

-- | Helper function to safely access nested JSON fields
(.:?) :: Value -> Text -> Maybe Value
(Object v) .:? key = v Data.Aeson..:? key
_ .:? _ = Nothing

-- | Token classification
classifyToken :: [Text] -> [Text] -> Text -> [(TokenType, Text)]
classifyToken keywords operators token
    | token `elem` keywords = [(Keyword, token)]
    | token `elem` operators = [(Operator, token)]
    | isStringLiteral token = [(String, token)]
    | isNumber token = [(Number, token)]
    | isIdentifier token = [(Identifier, token)]
    | isPunctuation token = [(Punctuation, token)]
    | otherwise = [(Other "unknown", token)]

-- | Check if token is a string literal
isStringLiteral :: Text -> Bool
isStringLiteral t =
    (T.head t == '"' && T.last t == '"') ||
    (T.head t == '\'' && T.last t == '\'')

-- | Check if token is a number
isNumber :: Text -> Bool
isNumber = T.all (\c -> c `elem` (['0'..'9'] ++ ['.', '-', '+', 'e', 'E']))

-- | Check if token is a valid identifier
isIdentifier :: Text -> Bool
isIdentifier t = case T.uncons t of
    Nothing -> False
    Just (c, rest) -> isValidStart c && T.all isValidChar rest
  where
    isValidStart c = c `elem` ('_' : ['a'..'z'] ++ ['A'..'Z'])
    isValidChar c = c `elem` ('_' : ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'])

-- | Check if token is punctuation
isPunctuation :: Text -> Bool
isPunctuation t = T.all (`elem` ".,;:()[]{}") t

-- | Process tokens into highlighted text with ranges
processTokens :: [(TokenType, Text)] -> Int -> Int -> [HighlightRange] -> (Text, [HighlightRange])
processTokens [] _ _ ranges = (T.empty, reverse ranges)
processTokens ((typ, text):rest) line col accum =
    let tokenClass = tokenTypeToClass typ
        range = HighlightRange
            { hrStartLine = line
            , hrStartCol = col
            , hrEndLine = line
            , hrEndCol = col + T.length text
            , hrTokenType = tokenTypeToText typ
            , hrTokenClass = tokenClass
            }
        (restText, restRanges) = processTokens rest line (col + T.length text) (range:accum)
    in (text <> restText, restRanges)

-- | Implementation of the diff algorithm using Myers' algorithm
diffLines :: [Text] -> [Text] -> [(Int, Int, Int, Int, [(DiffLineType, Text)])]
diffLines old new =
    let script = computeEditScript old new
        hunks = groupIntoHunks script
    in map (convertEditScriptToHunk old new) hunks

type Point = (Int, Int)  -- (x, y) coordinates in edit graph
type EditScript = [(EditOperation, Int)]  -- (operation, line number)
data EditOperation = Insert | Delete | Keep deriving (Show, Eq)

-- | Compute edit script using Myers' algorithm
computeEditScript :: [Text] -> [Text] -> EditScript
computeEditScript old new =
    let n = length old
        m = length new
        v0 = M.singleton 0 0  -- Initial D=0 diagonal
        (_, script) = go v0 0 [] 0
    in reverse script
  where
    go v d script k
        | k > d = go v (d + 1) script (-d)
        | k <= d =
            let down = k == -d || (k /= d && v M.! (k-1) < v M.! (k+1))
                kPrev = if down then k+1 else k-1
                xStart = v M.! kPrev
                xMid = if down then xStart else xStart + 1
                yMid = xMid - k
                (x, y, ops) = snake xMid yMid []
                v' = M.insert k x v
                script' = ops ++ script
            in if x >= n && y >= m
               then (v', script')
               else go v' d script' (k + 2)
        | otherwise = (v, script)

    snake :: Int -> Int -> [(EditOperation, Int)] -> (Int, Int, [(EditOperation, Int)])
    snake x y ops
        | x < n && y < m && old !! x == new !! y =
            snake (x+1) (y+1) ((Keep, x):ops)
        | otherwise = (x, y, ops)

-- | Group edit operations into hunks
groupIntoHunks :: EditScript -> [[EditOperation]]
groupIntoHunks = groupBy (\a b -> fst a == fst b) . filter ((/= Keep) . fst)

-- | Convert edit script hunk to diff format
convertEditScriptToHunk :: [Text] -> [Text] -> [EditOperation] -> (Int, Int, Int, Int, [(DiffLineType, Text)])
convertEditScriptToHunk old new ops =
    let oldStart = minimum [i | (Delete, i) <- ops]
        oldCount = length [() | (Delete, _) <- ops]
        newStart = minimum [i | (Insert, i) <- ops]
        newCount = length [() | (Insert, _) <- ops]
        lines = [(if op == Insert then Added else Removed,
                 if op == Insert then new !! i else old !! i)
                | (op, i) <- ops]
    in (oldStart, oldCount, newStart, newCount, lines)

-- | Compute line-level diff
computeLineDiff :: Text -> Text -> DiffInfo
computeLineDiff oldText newText =
    let oldLines = T.lines oldText
        newLines = T.lines newText
        hunks = diffLines oldLines newLines
        stats = calculateDiffStats hunks
    in DiffInfo
        { diOldPath = ""  -- Set by caller
        , diNewPath = ""  -- Set by caller
        , diOldContent = oldText
        , diNewContent = newText
        , diHunks = map convertHunk hunks
        , diStats = stats
        }
