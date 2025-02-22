{-|
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

module Gerrit.Models.CodeSearch where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types

-- | Code search index status
data IndexStatus =
    Pending
  | Indexing
  | Completed
  | Failed Text  -- ^ Error message if indexing failed
  deriving (Show, Read, Eq, Generic)

instance ToJSON IndexStatus
instance FromJSON IndexStatus

derivePersistField "IndexStatus"

-- | Code search configuration
data SearchConfig = SearchConfig
  { indexBatchSize :: Int  -- ^ Number of files to index in one batch
  , maxFileSize :: Int     -- ^ Maximum file size to index in bytes
  , excludePatterns :: [Text]  -- ^ File patterns to exclude from indexing
  , languageConfig :: Value    -- ^ Language-specific indexing configuration
  , indexSchedule :: Text      -- ^ Cron expression for index updates
  } deriving (Show, Generic)

instance ToJSON SearchConfig
instance FromJSON SearchConfig

derivePersistField "SearchConfig"

-- | Search result type
data SearchResultType =
    FileMatch       -- ^ Match in file content
  | SymbolMatch     -- ^ Match in symbol definition
  | CommitMatch     -- ^ Match in commit message
  | PathMatch       -- ^ Match in file path
  deriving (Show, Read, Eq, Generic)

instance ToJSON SearchResultType
instance FromJSON SearchResultType

derivePersistField "SearchResultType"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
CodeSearchIndex
    indexId Text
    repoId Text
    branch Text
    commitId Text
    status IndexStatus
    config SearchConfig
    lastIndexed UTCTime Maybe
    nextIndexTime UTCTime Maybe
    metadata Value Maybe
    created UTCTime
    updated UTCTime
    UniqueIndexId indexId
    UniqueRepoBranch repoId branch
    Foreign Repository repoId References repositories OnDeleteCascade
    deriving Show Eq Generic

SearchResult
    resultId Text
    indexId Text
    resultType SearchResultType
    filePath Text
    lineNumber Int Maybe
    columnNumber Int Maybe
    matchText Text
    context Text
    symbolName Text Maybe
    commitId Text Maybe
    score Double
    metadata Value Maybe
    timestamp UTCTime
    UniqueResultId resultId
    Foreign CodeSearchIndex indexId References code_search_indices OnDeleteCascade
    deriving Show Eq Generic

SearchQuery
    queryId Text
    userId Text
    query Text
    filters Value Maybe
    resultCount Int
    executionTime Double  -- ^ Query execution time in seconds
    timestamp UTCTime
    UniqueQueryId queryId
    deriving Show Eq Generic

IndexingJob
    jobId Text
    indexId Text
    status IndexStatus
    progress Double
    totalFiles Int
    processedFiles Int
    errorCount Int
    errors Value Maybe
    startTime UTCTime
    endTime UTCTime Maybe
    metadata Value Maybe
    UniqueJobId jobId
    Foreign CodeSearchIndex indexId References code_search_indices OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity CodeSearchIndex)
instance ToJSON CodeSearchIndex
instance FromJSON CodeSearchIndex

instance ToJSON (Entity SearchResult)
instance ToJSON SearchResult
instance FromJSON SearchResult

instance ToJSON (Entity SearchQuery)
instance ToJSON SearchQuery
instance FromJSON SearchQuery

instance ToJSON (Entity IndexingJob)
instance ToJSON IndexingJob
instance FromJSON IndexingJob
