-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Services.TeamService
    ( -- * Types
      TeamService(..)
    , TeamError(..)
      -- * Service Operations
    , initTeamService
    , createTeam
    , updateTeam
    , deleteTeam
    , getTeamById
    , listTeams
    , addTeamMember
    , removeTeamMember
    , updateMemberRole
    , getTeamMembers
    , getTeamHierarchy
    , validateTeamAccess
    ) where

import Control.Monad (void, when)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import Database.Persist
import Database.Persist.Sql

import Gerrit.Models.Team
import Gerrit.Models.Types
import Gerrit.Services.NotificationService (NotificationService)
import qualified Gerrit.Services.NotificationService as Notification
import Gerrit.Services.MetricsService (MetricsService)
import qualified Gerrit.Services.MetricsService as Metrics

-- | Team service errors
data TeamError
    = TeamNotFound Text
    | MemberNotFound Text
    | InvalidRole Text
    | InvalidVisibility Text
    | CyclicHierarchy Text
    | AccessDenied Text
    | DatabaseError Text
    deriving (Show, Eq)

-- | Team service
data TeamService = TeamService
    { teamPool :: ConnectionPool
    , teamNotificationService :: NotificationService
    , teamMetricsService :: MetricsService
    }

-- | Initialize team service
initTeamService :: ConnectionPool -> NotificationService -> MetricsService -> TeamService
initTeamService pool notificationSvc metricsSvc = TeamService
    { teamPool = pool
    , teamNotificationService = notificationSvc
    , teamMetricsService = metricsSvc
    }

-- | Create a new team
createTeam :: MonadIO m
           => TeamService
           -> Text  -- ^ Name
           -> Maybe Text  -- ^ Description
           -> Text  -- ^ Organization ID
           -> TeamVisibility  -- ^ Visibility
           -> Maybe Text  -- ^ Parent team ID
           -> Maybe Value  -- ^ Additional metadata
           -> Text  -- ^ Created by
           -> m (Either TeamError (Entity Team))
createTeam TeamService{..} name desc orgId visibility parentId metadata createdBy = do
    -- Validate parent team if specified
    case parentId of
        Just pid -> do
            mParent <- runSqlPool (getBy $ UniqueTeamId pid) teamPool
            case mParent of
                Nothing -> return $ Left $ TeamNotFound pid
                Just _ -> do
                    -- Check for cyclic hierarchy
                    hasCycle <- checkCyclicHierarchy pid []
                    when hasCycle $
                        return $ Left $ CyclicHierarchy "Cyclic team hierarchy detected"
        Nothing -> return $ Right ()

    -- Create team
    result <- runSqlPool (Gerrit.Models.Team.createTeam name desc orgId visibility parentId metadata) teamPool
    case result of
        Left err -> return $ Left $ DatabaseError $ T.pack $ show err
        Right team -> do
            -- Send notification
            void $ Notification.sendNotification teamNotificationService
                "team_created"
                (entityKey team)
                createdBy

            -- Record metrics
            void $ Metrics.recordMetric teamMetricsService
                "team_created"
                (entityKey team)

            return $ Right team

-- | Update team details
updateTeam :: MonadIO m
           => TeamService
           -> Entity Team
           -> Text  -- ^ Name
           -> Maybe Text  -- ^ Description
           -> TeamVisibility  -- ^ Visibility
           -> Maybe Text  -- ^ Parent team ID
           -> Maybe Value  -- ^ Additional metadata
           -> Text  -- ^ Updated by
           -> m (Either TeamError (Entity Team))
updateTeam TeamService{..} team name desc visibility parentId metadata updatedBy = do
    -- Validate parent team if specified
    case parentId of
        Just pid -> do
            mParent <- runSqlPool (getBy $ UniqueTeamId pid) teamPool
            case mParent of
                Nothing -> return $ Left $ TeamNotFound pid
                Just _ -> do
                    -- Check for cyclic hierarchy
                    hasCycle <- checkCyclicHierarchy pid []
                    when hasCycle $
                        return $ Left $ CyclicHierarchy "Cyclic team hierarchy detected"
        Nothing -> return $ Right ()

    -- Update team
    result <- runSqlPool (Gerrit.Models.Team.updateTeam team name desc visibility parentId metadata) teamPool
    case result of
        Left err -> return $ Left $ DatabaseError $ T.pack $ show err
        Right updatedTeam -> do
            -- Send notification
            void $ Notification.sendNotification teamNotificationService
                "team_updated"
                (entityKey updatedTeam)
                updatedBy

            -- Record metrics
            void $ Metrics.recordMetric teamMetricsService
                "team_updated"
                (entityKey updatedTeam)

            return $ Right updatedTeam

-- | Delete a team
deleteTeam :: MonadIO m
           => TeamService
           -> Entity Team
           -> Text  -- ^ Deleted by
           -> m (Either TeamError ())
deleteTeam TeamService{..} team deletedBy = do
    -- Check if team has children
    children <- runSqlPool (selectList [TeamParentTeamId ==. Just (teamTeamId $ entityVal team)] []) teamPool
    if not (null children)
        then return $ Left $ InvalidRole "Cannot delete team with child teams"
        else do
            -- Delete team
            runSqlPool (Gerrit.Models.Team.deleteTeam team) teamPool

            -- Send notification
            void $ Notification.sendNotification teamNotificationService
                "team_deleted"
                (entityKey team)
                deletedBy

            -- Record metrics
            void $ Metrics.recordMetric teamMetricsService
                "team_deleted"
                (entityKey team)

            return $ Right ()

-- | Get team by ID
getTeamById :: MonadIO m
            => TeamService
            -> Text  -- ^ Team ID
            -> m (Either TeamError (Entity Team))
getTeamById TeamService{..} teamId = do
    result <- runSqlPool (Gerrit.Models.Team.getTeamById teamId) teamPool
    case result of
        Nothing -> return $ Left $ TeamNotFound teamId
        Just team -> return $ Right team

-- | List teams with filtering
listTeams :: MonadIO m
          => TeamService
          -> Text  -- ^ Organization ID
          -> Maybe TeamVisibility  -- ^ Filter by visibility
          -> Int   -- ^ Offset
          -> Int   -- ^ Limit
          -> m [Entity Team]
listTeams TeamService{..} = Gerrit.Models.Team.listTeams teamPool

-- | Add a member to a team
addTeamMember :: MonadIO m
              => TeamService
              -> Text  -- ^ Team ID
              -> Text  -- ^ User ID
              -> TeamRole  -- ^ Role
              -> Text  -- ^ Added by
              -> Maybe Value  -- ^ Additional metadata
              -> m (Either TeamError (Entity TeamMember))
addTeamMember TeamService{..} teamId userId role addedBy metadata = do
    -- Check if team exists
    mTeam <- runSqlPool (getBy $ UniqueTeamId teamId) teamPool
    case mTeam of
        Nothing -> return $ Left $ TeamNotFound teamId
        Just _ -> do
            -- Add member
            result <- runSqlPool (Gerrit.Models.Team.addTeamMember teamId userId role addedBy metadata) teamPool
            case result of
                Left err -> return $ Left $ DatabaseError $ T.pack $ show err
                Right member -> do
                    -- Send notification
                    void $ Notification.sendNotification teamNotificationService
                        "team_member_added"
                        (entityKey member)
                        addedBy

                    -- Record metrics
                    void $ Metrics.recordMetric teamMetricsService
                        "team_member_added"
                        (entityKey member)

                    return $ Right member

-- | Remove a member from a team
removeTeamMember :: MonadIO m
                 => TeamService
                 -> Text  -- ^ Team ID
                 -> Text  -- ^ User ID
                 -> Text  -- ^ Removed by
                 -> m (Either TeamError ())
removeTeamMember TeamService{..} teamId userId removedBy = do
    -- Check if member exists
    mMember <- runSqlPool (getBy $ UniqueTeamMembership teamId userId) teamPool
    case mMember of
        Nothing -> return $ Left $ MemberNotFound userId
        Just member -> do
            -- Remove member
            runSqlPool (Gerrit.Models.Team.removeTeamMember teamId userId) teamPool

            -- Send notification
            void $ Notification.sendNotification teamNotificationService
                "team_member_removed"
                (entityKey member)
                removedBy

            -- Record metrics
            void $ Metrics.recordMetric teamMetricsService
                "team_member_removed"
                (entityKey member)

            return $ Right ()

-- | Update a member's role
updateMemberRole :: MonadIO m
                 => TeamService
                 -> Text  -- ^ Team ID
                 -> Text  -- ^ User ID
                 -> TeamRole  -- ^ New role
                 -> Text  -- ^ Updated by
                 -> m (Either TeamError (Entity TeamMember))
updateMemberRole TeamService{..} teamId userId newRole updatedBy = do
    result <- runSqlPool (Gerrit.Models.Team.updateMemberRole teamId userId newRole) teamPool
    case result of
        Nothing -> return $ Left $ MemberNotFound userId
        Just member -> do
            -- Send notification
            void $ Notification.sendNotification teamNotificationService
                "team_member_role_updated"
                (entityKey member)
                updatedBy

            -- Record metrics
            void $ Metrics.recordMetric teamMetricsService
                "team_member_role_updated"
                (entityKey member)

            return $ Right member

-- | Get team members
getTeamMembers :: MonadIO m
               => TeamService
               -> Text  -- ^ Team ID
               -> Maybe TeamRole  -- ^ Filter by role
               -> m [Entity TeamMember]
getTeamMembers TeamService{..} = Gerrit.Models.Team.getTeamMembers teamPool

-- | Get team hierarchy
getTeamHierarchy :: MonadIO m
                 => TeamService
                 -> Text  -- ^ Team ID
                 -> m (Either TeamError [(Entity Team, Int)])  -- ^ Teams with their depth in hierarchy
getTeamHierarchy TeamService{..} teamId = do
    mTeam <- runSqlPool (getBy $ UniqueTeamId teamId) teamPool
    case mTeam of
        Nothing -> return $ Left $ TeamNotFound teamId
        Just team -> do
            hierarchy <- getHierarchy team 0 []
            return $ Right hierarchy
  where
    getHierarchy :: MonadIO m => Entity Team -> Int -> [(Entity Team, Int)] -> m [(Entity Team, Int)]
    getHierarchy team depth acc = do
        children <- runSqlPool
            (selectList [TeamParentTeamId ==. Just (teamTeamId $ entityVal team)] [])
            teamPool
        foldM (\acc' child -> getHierarchy child (depth + 1) acc') ((team, depth) : acc) children

-- | Validate team access
validateTeamAccess :: MonadIO m
                  => TeamService
                  -> Text  -- ^ Team ID
                  -> Text  -- ^ User ID
                  -> TeamRole  -- ^ Required role
                  -> m (Either TeamError Bool)
validateTeamAccess TeamService{..} teamId userId requiredRole = do
    -- Get user's role in team
    mMember <- runSqlPool (getBy $ UniqueTeamMembership teamId userId) teamPool
    case mMember of
        Nothing -> return $ Left $ MemberNotFound userId
        Just (Entity _ member) ->
            -- Compare roles
            return $ Right $ teamMemberRole member >= requiredRole

-- Helper functions

-- | Check for cyclic hierarchy
checkCyclicHierarchy :: MonadIO m => Text -> [Text] -> m Bool
checkCyclicHierarchy teamId visited
    | teamId `elem` visited = return True
    | otherwise = do
        mTeam <- runSqlPool (getBy $ UniqueTeamId teamId) teamPool
        case mTeam of
            Nothing -> return False
            Just (Entity _ team) ->
                case teamParentTeamId team of
                    Nothing -> return False
                    Just parentId -> checkCyclicHierarchy parentId (teamId : visited)
