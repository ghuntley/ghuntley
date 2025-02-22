-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Gerrit.Web.Handlers where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Database.Persist
import Yesod
import Yesod.Form
import Data.Swagger (Swagger)
import Servant.Swagger.UI (swaggerSchemaUIServer)

import Gerrit.Models.Types
import Gerrit.Web.Foundation
import Gerrit.Web.Docs (generateSwagger, swaggerUIServer)
import Gerrit.Database.Connection (runDB)
import qualified Gerrit.Git.Operations as Git

-- | Serve OpenAPI/Swagger JSON specification
getSwaggerJsonR :: Handler Value
getSwaggerJsonR = returnJson generateSwagger

-- | Serve Swagger UI
getSwaggerUIR :: Handler Html
getSwaggerUIR = defaultLayout $ do
    setTitle "API Documentation"
    [whamlet|
        <div .container>
            <h1>API Documentation
            <div #swagger-ui>
    |]
    toWidget [lucius|
        #swagger-ui {
            height: calc(100vh - 100px);
            margin: 20px 0;
        }
    |]
    addStylesheetRemote "https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui.css"
    addScriptRemote "https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-bundle.js"
    addScriptRemote "https://unpkg.com/swagger-ui-dist@5.11.0/swagger-ui-standalone-preset.js"
    toWidget [julius|
        window.onload = function() {
            const ui = SwaggerUIBundle({
                url: "@{SwaggerJsonR}",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
            window.ui = ui;
        };
    |]

-- | Home page
getHomeR :: Handler Html
getHomeR = defaultLayout $ do
    setTitle "Gerrit Code Review"
    $(widgetFile "home")

-- | List and create projects
getProjectsR :: Handler Html
getProjectsR = do
    projects <- runDB configPool $ selectList [] [Asc ProjectName]
    defaultLayout $ do
        setTitle "Projects"
        $(widgetFile "projects/list")

postProjectsR :: Handler Html
postProjectsR = do
    ((result, widget), enctype) <- runFormPost projectForm
    case result of
        FormSuccess project -> do
            now <- liftIO getCurrentTime
            _ <- runDB configPool $ insert project
            redirect ProjectsR
        _ -> defaultLayout $ do
            setTitle "Create Project"
            $(widgetFile "projects/new")

-- | View a single project
getProjectR :: Text -> Handler Html
getProjectR name = do
    project <- runDB configPool $ getBy404 $ UniqueProjectName name
    changes <- runDB configPool $ selectList
        [ChangeProjectId ==. entityKey project]
        [Desc ChangeCreatedAt]
    defaultLayout $ do
        setTitle $ "Project: " <> name
        $(widgetFile "projects/show")

-- | List and create changes
getChangesR :: Handler Html
getChangesR = do
    changes <- runDB configPool $ selectList [] [Desc ChangeCreatedAt]
    defaultLayout $ do
        setTitle "Changes"
        $(widgetFile "changes/list")

postChangesR :: Handler Html
postChangesR = do
    ((result, widget), enctype) <- runFormPost changeForm
    case result of
        FormSuccess change -> do
            now <- liftIO getCurrentTime
            _ <- runDB configPool $ insert change
            redirect ChangesR
        _ -> defaultLayout $ do
            setTitle "Create Change"
            $(widgetFile "changes/new")

-- | View a single change
getChangeR :: Text -> Handler Html
getChangeR changeId = do
    change <- runDB configPool $ get404 $ toKey changeId
    revisions <- runDB configPool $ selectList
        [RevisionChangeId ==. toKey changeId]
        [Desc RevisionNumber]
    reviews <- runDB configPool $ selectList
        [ReviewChangeId ==. toKey changeId]
        [Desc ReviewCreatedAt]
    defaultLayout $ do
        setTitle $ "Change: " <> changeSubject change
        $(widgetFile "changes/show")

-- | View change diff
getChangeDiffR :: Text -> Handler Html
getChangeDiffR changeId = do
    change <- runDB configPool $ get404 $ toKey changeId
    project <- runDB configPool $ get404 $ changeProjectId change
    mRevision <- runDB configPool $ selectFirst
        [RevisionChangeId ==. toKey changeId]
        [Desc RevisionNumber]
    case mRevision of
        Nothing -> notFound
        Just (Entity _ revision) -> do
            gitPath <- getsYesod appGitBasePath
            let repo = gitPath </> T.unpack (projectName project)
            result <- liftIO $ runExceptT $ Git.getDiff repo
                (revisionParentHash revision)
                (revisionCommitHash revision)
            case result of
                Left err -> invalidArgs [T.pack $ show err]
                Right diffs -> defaultLayout $ do
                    setTitle "Change Diff"
                    $(widgetFile "changes/diff")

-- | User profile
getProfileR :: Handler Html
getProfileR = do
    muser <- maybeAuth
    case muser of
        Nothing -> notFound
        Just (Entity userId user) -> do
            changes <- runDB configPool $ selectList
                [ChangeAuthorId ==. userId]
                [Desc ChangeCreatedAt]
            reviews <- runDB configPool $ selectList
                [ReviewReviewerId ==. userId]
                [Desc ReviewCreatedAt]
            defaultLayout $ do
                setTitle "Profile"
                $(widgetFile "profile")

-- Forms

projectForm :: Form Project
projectForm = renderBootstrap3 BootstrapBasicForm $ Project
    <$> areq textField "Name" Nothing
    <*> aopt textField "Description" Nothing
    <*> areq (selectField userOptions) "Owner" Nothing
    <*> lift (liftIO getCurrentTime)
  where
    userOptions = optionsPersist [] [Asc UserName] userEmail

changeForm :: Form Change
changeForm = renderBootstrap3 BootstrapBasicForm $ Change
    <$> areq (selectField projectOptions) "Project" Nothing
    <*> areq textField "Branch" Nothing
    <*> areq textField "Subject" Nothing
    <*> areq textareaField "Message" Nothing
    <*> areq (selectField userOptions) "Author" Nothing
    <*> pure Draft
    <*> lift (liftIO getCurrentTime)
    <*> lift (liftIO getCurrentTime)
  where
    projectOptions = optionsPersist [] [Asc ProjectName] projectName
    userOptions = optionsPersist [] [Asc UserName] userEmail

-- Helper functions

toKey :: Text -> Key a
toKey = fromJust . fromPathPiece
