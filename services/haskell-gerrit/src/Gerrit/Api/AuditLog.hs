-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.AuditLog
    ( AuditLogAPI
    , auditLogServer
    ) where

import Control.Monad.IO.Class (liftIO)
import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Servant
import Servant.Auth.Server

import qualified Data.UUID as UUID

import Gerrit.Models.AuditLog
import Gerrit.Models.Enterprise
import Gerrit.Auth (AuthenticatedUser(..))

-- | API for accessing audit logs
type AuditLogAPI =
    -- Query audit logs with filtering
    "audit" :> "logs" :>
    Auth '[JWT] AuthenticatedUser :>
    QueryParam "start_time" UTCTime :>
    QueryParam "end_time" UTCTime :>
    QueryParam "action" AuditAction :>
    QueryParam "limit" Int :>
    QueryParam "offset" Int :>
    Get '[JSON] [AuditLogEntry]

    -- Stream audit logs in real-time
    :<|> "audit" :> "logs" :> "stream" :>
    Auth '[JWT] AuthenticatedUser :>
    StreamGet NewlineFraming JSON AuditLogEntry

    -- Export audit logs
    :<|> "audit" :> "logs" :> "export" :>
    Auth '[JWT] AuthenticatedUser :>
    QueryParam "format" ExportFormat :>
    Get '[JSON] FilePath

-- | Server implementation
auditLogServer :: Connection -> ServerT AuditLogAPI Handler
auditLogServer conn = queryLogs
                :<|> streamLogs
                :<|> exportLogs
  where
    queryLogs auth start end action limit offset = do
        user <- validateUser auth
        let enterpriseId = userEnterpriseId user
            defaultLimit = 100
            defaultOffset = 0
        logs <- liftIO $ queryAuditLogs conn
                enterpriseId
                start
                end
                action
                (maybe defaultLimit (min 1000) limit)
                (fromMaybe defaultOffset offset)
        pure logs

    streamLogs auth = do
        user <- validateUser auth
        let enterpriseId = userEnterpriseId user
        streamAuditLogs conn enterpriseId $ \entry ->
            liftIO $ putStrLn $ "Streaming entry: " ++ show entry

    exportLogs auth format = do
        user <- validateUser auth
        let enterpriseId = userEnterpriseId user
            defaultFormat = JSON
        path <- liftIO $ do
            uuid <- UUID.nextRandom
            let fileName = "audit_logs_" <> show uuid
            exportAuditLogs conn
                enterpriseId
                fileName
                (fromMaybe defaultFormat format)
            pure fileName
        pure path

-- | Validate user has access to audit logs
validateUser :: AuthResult AuthenticatedUser -> Handler AuthenticatedUser
validateUser (Authenticated user)
    | hasAuditLogAccess user = pure user
    | otherwise = throwError err403
validateUser _ = throwError err401

-- | Check if user has audit log access
hasAuditLogAccess :: AuthenticatedUser -> Bool
hasAuditLogAccess user =
    "audit:read" `elem` userPermissions user
