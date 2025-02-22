{-
 Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module Gerrit.Api.Config
    ( -- * Configuration
      Config(..)
    , Environment(..)
    , LogConfig(..)
    , DatabaseConfig(..)
      -- * Loading
    , loadConfig
    , defaultConfig
    , validateConfig
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Logger (LogLevel(..))
import Data.Text (Text)
import Data.Time (NominalDiffTime)
import System.Environment (lookupEnv)
import qualified Data.Text as Text
import GHC.Generics

-- | Application environment
data Environment
    = Development
    | Staging
    | Production
    deriving (Show, Eq, Generic)

-- | Logging configuration
data LogConfig = LogConfig
    { logLevel :: Text
    , logFormat :: Text
    , logPath :: FilePath
    } deriving (Show, Eq, Generic)

-- | Database configuration
data DatabaseConfig = DatabaseConfig
    { dbHost :: Text
    , dbPort :: Int
    , dbName :: Text
    , dbUser :: Text
    , dbPassword :: Text
    , dbPoolSize :: Int
    , dbPoolIdleTimeout :: NominalDiffTime  -- ^ Seconds before closing idle connections
    , dbPoolMaxLifetime :: NominalDiffTime  -- ^ Maximum lifetime of a connection in seconds
    , dbPoolStripes :: Int                  -- ^ Number of stripes (sub-pools)
    , dbLogLevel :: LogLevel                -- ^ Database logging level
    , dbEnableSSL :: Bool                   -- ^ Enable SSL connection
    , dbSSLMode :: Text                     -- ^ SSL mode (disable, allow, prefer, require, verify-ca, verify-full)
    , dbSSLCert :: Maybe Text               -- ^ Path to client certificate
    , dbSSLKey :: Maybe Text                -- ^ Path to client key
    , dbSSLRootCert :: Maybe Text           -- ^ Path to root certificate
    } deriving (Show, Eq, Generic)

-- | Main configuration
data Config = Config
    { configEnvironment :: Environment
    , configPort :: Int
    , configHost :: Text
    , configBaseUrl :: Text
    , configSecretKey :: Text
    , configDatabase :: DatabaseConfig
    , configLogging :: LogConfig
    , configGitBasePath :: FilePath
    , configMaxUploadSize :: Int
    -- Slack configuration
    , configSlackWebhookUrl :: Text
    , configSlackToken :: Maybe Text
    , configSlackEnabled :: Bool
    , configSlackDefaultChannel :: Text
    -- Email configuration
    , configEmailEnabled :: Bool
    , configEmailApiUrl :: Text
    , configEmailApiKey :: Maybe Text
    , configEmailFromAddress :: Text
    , configEmailFromName :: Text
    , configEmailDefaultRecipients :: [Text]
    -- SMTP configuration
    , configSmtpEnabled :: Bool
    , configSmtpHost :: Text
    , configSmtpPort :: Int
    , configSmtpUsername :: Maybe Text
    , configSmtpPassword :: Maybe Text
    , configSmtpUseTLS :: Bool
    , configSmtpUseSTARTTLS :: Bool
    , configSmtpAuthMethod :: Text
    , configSmtpTimeout :: Int
    -- Teams configuration
    , configTeamsWebhookUrl :: Text
    , configTeamsEnabled :: Bool
    -- Discord configuration
    , configDiscordWebhookUrl :: Text
    , configDiscordEnabled :: Bool
    -- PagerDuty configuration
    , configPagerDutyApiUrl :: Text
    , configPagerDutyToken :: Maybe Text
    , configPagerDutyEnabled :: Bool
    , configPagerDutyDefaultPriority :: Maybe Text
    } deriving (Show, Eq, Generic)

-- | Default configuration values
defaultConfig :: Config
defaultConfig = Config
    { configEnvironment = Development
    , configPort = 8080
    , configHost = "localhost"
    , configBaseUrl = "http://localhost:8080"
    , configSecretKey = "change-me-in-production"
    , configDatabase = DatabaseConfig
        { dbHost = "localhost"
        , dbPort = 5432
        , dbName = "gerrit"
        , dbUser = "gerrit"
        , dbPassword = "gerrit"
        , dbPoolSize = 10
        , dbPoolIdleTimeout = 300  -- 5 minutes
        , dbPoolMaxLifetime = 3600  -- 1 hour
        , dbPoolStripes = 2
        , dbLogLevel = LevelWarn
        , dbEnableSSL = False
        , dbSSLMode = "disable"
        , dbSSLCert = Nothing
        , dbSSLKey = Nothing
        , dbSSLRootCert = Nothing
        }
    , configLogging = LogConfig
        { logLevel = "info"
        , logFormat = "json"
        , logPath = "logs/gerrit.log"
        }
    , configGitBasePath = "/var/lib/gerrit/git"
    , configMaxUploadSize = 10 * 1024 * 1024  -- 10MB
    -- Slack defaults
    , configSlackWebhookUrl = ""
    , configSlackToken = Nothing
    , configSlackEnabled = False
    , configSlackDefaultChannel = "gerrit-alerts"
    -- Email defaults
    , configEmailEnabled = False
    , configEmailApiUrl = ""
    , configEmailApiKey = Nothing
    , configEmailFromAddress = "gerrit@localhost"
    , configEmailFromName = "Gerrit Alert System"
    , configEmailDefaultRecipients = []
    -- SMTP defaults
    , configSmtpEnabled = False
    , configSmtpHost = "localhost"
    , configSmtpPort = 25
    , configSmtpUsername = Nothing
    , configSmtpPassword = Nothing
    , configSmtpUseTLS = False
    , configSmtpUseSTARTTLS = False
    , configSmtpAuthMethod = "PLAIN"
    , configSmtpTimeout = 60
    -- Teams defaults
    , configTeamsWebhookUrl = ""
    , configTeamsEnabled = False
    -- Discord defaults
    , configDiscordWebhookUrl = ""
    , configDiscordEnabled = False
    -- PagerDuty defaults
    , configPagerDutyApiUrl = "https://events.pagerduty.com/v2/enqueue"
    , configPagerDutyToken = Nothing
    , configPagerDutyEnabled = False
    , configPagerDutyDefaultPriority = Just "P2"
    }

-- | Load configuration from environment variables
loadConfig :: MonadIO m => m Config
loadConfig = do
    -- Environment
    mEnv <- liftIO $ lookupEnv "GERRIT_ENV"
    let env = case mEnv of
            Just "production" -> Production
            Just "staging" -> Staging
            _ -> Development

    -- Server settings
    mPort <- liftIO $ lookupEnv "GERRIT_PORT"
    mHost <- liftIO $ lookupEnv "GERRIT_HOST"
    mBaseUrl <- liftIO $ lookupEnv "GERRIT_BASE_URL"
    mSecretKey <- liftIO $ lookupEnv "GERRIT_SECRET_KEY"

    -- Database settings
    mDbHost <- liftIO $ lookupEnv "GERRIT_DB_HOST"
    mDbPort <- liftIO $ lookupEnv "GERRIT_DB_PORT"
    mDbName <- liftIO $ lookupEnv "GERRIT_DB_NAME"
    mDbUser <- liftIO $ lookupEnv "GERRIT_DB_USER"
    mDbPass <- liftIO $ lookupEnv "GERRIT_DB_PASSWORD"
    mDbPool <- liftIO $ lookupEnv "GERRIT_DB_POOL_SIZE"
    mDbPoolIdle <- liftIO $ lookupEnv "GERRIT_DB_POOL_IDLE_TIMEOUT"
    mDbPoolLife <- liftIO $ lookupEnv "GERRIT_DB_POOL_MAX_LIFETIME"
    mDbPoolStripes <- liftIO $ lookupEnv "GERRIT_DB_POOL_STRIPES"
    mDbLogLevel <- liftIO $ lookupEnv "GERRIT_DB_LOG_LEVEL"
    mDbEnableSSL <- liftIO $ lookupEnv "GERRIT_DB_ENABLE_SSL"
    mDbSSLMode <- liftIO $ lookupEnv "GERRIT_DB_SSL_MODE"
    mDbSSLCert <- liftIO $ lookupEnv "GERRIT_DB_SSL_CERT"
    mDbSSLKey <- liftIO $ lookupEnv "GERRIT_DB_SSL_KEY"
    mDbSSLRootCert <- liftIO $ lookupEnv "GERRIT_DB_SSL_ROOT_CERT"

    -- Logging settings
    mLogLevel <- liftIO $ lookupEnv "GERRIT_LOG_LEVEL"
    mLogFormat <- liftIO $ lookupEnv "GERRIT_LOG_FORMAT"
    mLogPath <- liftIO $ lookupEnv "GERRIT_LOG_PATH"

    -- Git settings
    mGitPath <- liftIO $ lookupEnv "GERRIT_GIT_PATH"
    mMaxUpload <- liftIO $ lookupEnv "GERRIT_MAX_UPLOAD_SIZE"

    -- Slack settings
    mSlackUrl <- liftIO $ lookupEnv "GERRIT_SLACK_WEBHOOK_URL"
    mSlackToken <- liftIO $ lookupEnv "GERRIT_SLACK_TOKEN"
    mSlackEnabled <- liftIO $ lookupEnv "GERRIT_SLACK_ENABLED"
    mSlackChannel <- liftIO $ lookupEnv "GERRIT_SLACK_DEFAULT_CHANNEL"

    -- Email settings
    mEmailEnabled <- liftIO $ lookupEnv "GERRIT_EMAIL_ENABLED"
    mEmailApiUrl <- liftIO $ lookupEnv "GERRIT_EMAIL_API_URL"
    mEmailApiKey <- liftIO $ lookupEnv "GERRIT_EMAIL_API_KEY"
    mEmailFromAddr <- liftIO $ lookupEnv "GERRIT_EMAIL_FROM_ADDRESS"
    mEmailFromName <- liftIO $ lookupEnv "GERRIT_EMAIL_FROM_NAME"
    mEmailRecipients <- liftIO $ lookupEnv "GERRIT_EMAIL_DEFAULT_RECIPIENTS"

    -- SMTP settings
    mSmtpEnabled <- liftIO $ lookupEnv "GERRIT_SMTP_ENABLED"
    mSmtpHost <- liftIO $ lookupEnv "GERRIT_SMTP_HOST"
    mSmtpPort <- liftIO $ lookupEnv "GERRIT_SMTP_PORT"
    mSmtpUsername <- liftIO $ lookupEnv "GERRIT_SMTP_USERNAME"
    mSmtpPassword <- liftIO $ lookupEnv "GERRIT_SMTP_PASSWORD"
    mSmtpUseTLS <- liftIO $ lookupEnv "GERRIT_SMTP_USE_TLS"
    mSmtpUseSTARTTLS <- liftIO $ lookupEnv "GERRIT_SMTP_USE_STARTTLS"
    mSmtpAuthMethod <- liftIO $ lookupEnv "GERRIT_SMTP_AUTH_METHOD"
    mSmtpTimeout <- liftIO $ lookupEnv "GERRIT_SMTP_TIMEOUT"

    -- Teams settings
    mTeamsUrl <- liftIO $ lookupEnv "GERRIT_TEAMS_WEBHOOK_URL"
    mTeamsEnabled <- liftIO $ lookupEnv "GERRIT_TEAMS_ENABLED"

    -- Discord settings
    mDiscordUrl <- liftIO $ lookupEnv "GERRIT_DISCORD_WEBHOOK_URL"
    mDiscordEnabled <- liftIO $ lookupEnv "GERRIT_DISCORD_ENABLED"

    -- PagerDuty settings
    mPagerDutyUrl <- liftIO $ lookupEnv "GERRIT_PAGERDUTY_API_URL"
    mPagerDutyToken <- liftIO $ lookupEnv "GERRIT_PAGERDUTY_TOKEN"
    mPagerDutyEnabled <- liftIO $ lookupEnv "GERRIT_PAGERDUTY_ENABLED"
    mPagerDutyPriority <- liftIO $ lookupEnv "GERRIT_PAGERDUTY_DEFAULT_PRIORITY"

    let dbConfig = (configDatabase defaultConfig)
            { dbHost = maybe (dbHost $ configDatabase defaultConfig) Text.pack mDbHost
            , dbPort = maybe (dbPort $ configDatabase defaultConfig) read mDbPort
            , dbName = maybe (dbName $ configDatabase defaultConfig) Text.pack mDbName
            , dbUser = maybe (dbUser $ configDatabase defaultConfig) Text.pack mDbUser
            , dbPassword = maybe (dbPassword $ configDatabase defaultConfig) Text.pack mDbPass
            , dbPoolSize = maybe (dbPoolSize $ configDatabase defaultConfig) read mDbPool
            , dbPoolIdleTimeout = maybe (dbPoolIdleTimeout $ configDatabase defaultConfig) (fromIntegral . read) mDbPoolIdle
            , dbPoolMaxLifetime = maybe (dbPoolMaxLifetime $ configDatabase defaultConfig) (fromIntegral . read) mDbPoolLife
            , dbPoolStripes = maybe (dbPoolStripes $ configDatabase defaultConfig) read mDbPoolStripes
            , dbLogLevel = maybe (dbLogLevel $ configDatabase defaultConfig) parseLogLevel mDbLogLevel
            , dbEnableSSL = maybe (dbEnableSSL $ configDatabase defaultConfig) (== "true") mDbEnableSSL
            , dbSSLMode = maybe (dbSSLMode $ configDatabase defaultConfig) Text.pack mDbSSLMode
            , dbSSLCert = fmap Text.pack mDbSSLCert <|> dbSSLCert (configDatabase defaultConfig)
            , dbSSLKey = fmap Text.pack mDbSSLKey <|> dbSSLKey (configDatabase defaultConfig)
            , dbSSLRootCert = fmap Text.pack mDbSSLRootCert <|> dbSSLRootCert (configDatabase defaultConfig)
            }

    return $ Config
        { configEnvironment = env
        , configPort = maybe (configPort defaultConfig) read mPort
        , configHost = maybe (configHost defaultConfig) Text.pack mHost
        , configBaseUrl = maybe (configBaseUrl defaultConfig) Text.pack mBaseUrl
        , configSecretKey = maybe (configSecretKey defaultConfig) Text.pack mSecretKey
        , configDatabase = dbConfig
        , configLogging = LogConfig
            { logLevel = maybe (logLevel $ configLogging defaultConfig) Text.pack mLogLevel
            , logFormat = maybe (logFormat $ configLogging defaultConfig) Text.pack mLogFormat
            , logPath = maybe (logPath $ configLogging defaultConfig) id mLogPath
            }
        , configGitBasePath = maybe (configGitBasePath defaultConfig) id mGitPath
        , configMaxUploadSize = maybe (configMaxUploadSize defaultConfig) read mMaxUpload
        , configSlackWebhookUrl = maybe (configSlackWebhookUrl defaultConfig) Text.pack mSlackUrl
        , configSlackToken = fmap Text.pack mSlackToken <|> configSlackToken defaultConfig
        , configSlackEnabled = maybe (configSlackEnabled defaultConfig) (== "true") mSlackEnabled
        , configSlackDefaultChannel = maybe (configSlackDefaultChannel defaultConfig) Text.pack mSlackChannel
        , configEmailEnabled = maybe (configEmailEnabled defaultConfig) (== "true") mEmailEnabled
        , configEmailApiUrl = maybe (configEmailApiUrl defaultConfig) Text.pack mEmailApiUrl
        , configEmailApiKey = fmap Text.pack mEmailApiKey <|> configEmailApiKey defaultConfig
        , configEmailFromAddress = maybe (configEmailFromAddress defaultConfig) Text.pack mEmailFromAddr
        , configEmailFromName = maybe (configEmailFromName defaultConfig) Text.pack mEmailFromName
        , configEmailDefaultRecipients = maybe (configEmailDefaultRecipients defaultConfig)
                                             (map Text.pack . splitOn "," . filter (/= ' '))
                                             mEmailRecipients
        , configSmtpEnabled = maybe (configSmtpEnabled defaultConfig) (== "true") mSmtpEnabled
        , configSmtpHost = maybe (configSmtpHost defaultConfig) Text.pack mSmtpHost
        , configSmtpPort = maybe (configSmtpPort defaultConfig) read mSmtpPort
        , configSmtpUsername = fmap Text.pack mSmtpUsername <|> configSmtpUsername defaultConfig
        , configSmtpPassword = fmap Text.pack mSmtpPassword <|> configSmtpPassword defaultConfig
        , configSmtpUseTLS = maybe (configSmtpUseTLS defaultConfig) (== "true") mSmtpUseTLS
        , configSmtpUseSTARTTLS = maybe (configSmtpUseSTARTTLS defaultConfig) (== "true") mSmtpUseSTARTTLS
        , configSmtpAuthMethod = maybe (configSmtpAuthMethod defaultConfig) Text.pack mSmtpAuthMethod
        , configSmtpTimeout = maybe (configSmtpTimeout defaultConfig) read mSmtpTimeout
        , configTeamsWebhookUrl = maybe (configTeamsWebhookUrl defaultConfig) Text.pack mTeamsUrl
        , configTeamsEnabled = maybe (configTeamsEnabled defaultConfig) (== "true") mTeamsEnabled
        , configDiscordWebhookUrl = maybe (configDiscordWebhookUrl defaultConfig) Text.pack mDiscordUrl
        , configDiscordEnabled = maybe (configDiscordEnabled defaultConfig) (== "true") mDiscordEnabled
        , configPagerDutyApiUrl = maybe (configPagerDutyApiUrl defaultConfig) Text.pack mPagerDutyUrl
        , configPagerDutyToken = fmap Text.pack mPagerDutyToken <|> configPagerDutyToken defaultConfig
        , configPagerDutyEnabled = maybe (configPagerDutyEnabled defaultConfig) (== "true") mPagerDutyEnabled
        , configPagerDutyDefaultPriority = fmap Text.pack mPagerDutyPriority <|> configPagerDutyDefaultPriority defaultConfig
        }

-- | Parse log level from text
parseLogLevel :: String -> LogLevel
parseLogLevel level = case Text.toLower (Text.pack level) of
    "debug" -> LevelDebug
    "info" -> LevelInfo
    "warn" -> LevelWarn
    "error" -> LevelError
    _ -> LevelInfo

-- | Split string on delimiter
splitOn :: Char -> String -> [String]
splitOn delim = filter (not . null) . map trim . split delim
  where
    split d [] = [[]]
    split d (c:cs)
        | c == d = [] : split d cs
        | otherwise = case split d cs of
            (x:xs) -> (c:x) : xs
            [] -> [[c]]

-- | Trim whitespace from string
trim :: String -> String
trim = dropWhile isSpace . reverse . dropWhile isSpace . reverse
  where
    isSpace = (== ' ')
