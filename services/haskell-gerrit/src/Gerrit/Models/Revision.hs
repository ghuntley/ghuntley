{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Models.Revision
    ( -- * Types
      Revision(..)
    , RevisionId
      -- * Operations
    , createRevision
    , getRevisionById
    , getChangeRevisions
    , getLatestRevision
    , migrateAll
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Change (Change)

-- | Define the Revision entity using persistent
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Revision
    revisionId Text
    changeId Text
    number Int
    commitId Text
    uploaderId Text
    description Text Maybe
    created UTCTime
    updated UTCTime
    UniqueRevisionId revisionId
    UniqueChangeRevision changeId number
    Foreign Change changeId References changes OnDeleteCascade
    deriving Show Eq Generic
|]

-- | Create a new revision
createRevision :: MonadIO m
               => ConnectionPool
               -> Text  -- ^ Change ID
               -> Text  -- ^ Commit ID
               -> Text  -- ^ Uploader ID
               -> Maybe Text  -- ^ Description
               -> m (Entity Revision)
createRevision pool changeId' commitId' uploaderId' description' = do
    now <- liftIO getCurrentTime
    -- Get the next revision number for this change
    currentRevs <- runSqlPool (selectList [RevisionChangeId ==. changeId'] [Desc RevisionNumber]) pool
    let nextNumber = maybe 1 ((+1) . revisionNumber . entityVal) (listToMaybe currentRevs)
    let revisionId' = generateRevisionId changeId' nextNumber
    let revision = Revision
            { revisionRevisionId = revisionId'
            , revisionChangeId = changeId'
            , revisionNumber = nextNumber
            , revisionCommitId = commitId'
            , revisionUploaderId = uploaderId'
            , revisionDescription = description'
            , revisionCreated = now
            , revisionUpdated = now
            }
    runSqlPool (insertEntity revision) pool

-- | Get a revision by ID
getRevisionById :: MonadIO m
                => ConnectionPool
                -> Text  -- ^ Revision ID
                -> m (Maybe (Entity Revision))
getRevisionById pool revisionId' =
    runSqlPool (getBy $ UniqueRevisionId revisionId') pool

-- | Get all revisions for a change
getChangeRevisions :: MonadIO m
                   => ConnectionPool
                   -> Text  -- ^ Change ID
                   -> m [Entity Revision]
getChangeRevisions pool changeId' =
    runSqlPool (selectList [RevisionChangeId ==. changeId'] [Asc RevisionNumber]) pool

-- | Get the latest revision for a change
getLatestRevision :: MonadIO m
                  => ConnectionPool
                  -> Text  -- ^ Change ID
                  -> m (Maybe (Entity Revision))
getLatestRevision pool changeId' =
    runSqlPool (selectFirst [RevisionChangeId ==. changeId'] [Desc RevisionNumber]) pool

-- | Helper function to generate a unique revision ID
generateRevisionId :: Text -> Int -> Text
generateRevisionId changeId number =
    changeId <> "-" <> Text.pack (show number)
