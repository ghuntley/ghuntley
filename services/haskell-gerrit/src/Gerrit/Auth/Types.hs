-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Auth.Types
    ( AuthProvider(..)
    , LDAPConfig(..)
    , LDAPServer(..)
    , LDAPAttributes(..)
    , OAuthConfig(..)
    , OAuthProvider(..)
    , AuthResult(..)
    , AuthToken(..)
    , TokenType(..)
    , AuthError(..)
    , Challenge(..)
    , User(..)
    , Role(..)
    , Permission(..)
    ) where

import Control.Exception (Exception)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics (Generic)

-- | Authentication provider type
data AuthProvider
    = LDAPProvider LDAPConfig
    | OAuthProvider OAuthConfig
    | LocalProvider
    deriving (Show, Eq, Generic)

-- | LDAP configuration
data LDAPConfig = LDAPConfig
    { ldapServers :: [LDAPServer]        -- Multiple servers for failover
    , ldapBindDN :: Text                 -- Bind DN for service account
    , ldapBindPassword :: Text           -- Bind password
    , ldapUserBaseDN :: Text             -- Base DN for user search
    , ldapGroupBaseDN :: Text            -- Base DN for group search
    , ldapUserFilter :: Text             -- User search filter
    , ldapGroupFilter :: Text            -- Group search filter
    , ldapAttributes :: LDAPAttributes   -- Attribute mappings
    , ldapGroupSync :: Bool              -- Enable group synchronization
    , ldapTLS :: Bool                    -- Enable TLS
    , ldapPoolSize :: Int                -- Connection pool size
    } deriving (Show, Eq, Generic)

-- | LDAP server configuration
data LDAPServer = LDAPServer
    { ldapHost :: Text
    , ldapPort :: Int
    , ldapPriority :: Int               -- Lower number = higher priority
    } deriving (Show, Eq, Generic)

-- | LDAP attribute mappings
data LDAPAttributes = LDAPAttributes
    { attrUsername :: Text              -- Username attribute
    , attrEmail :: Text                 -- Email attribute
    , attrFullName :: Text              -- Full name attribute
    , attrGroups :: Text                -- Groups attribute/DN
    } deriving (Show, Eq, Generic)

-- | OAuth configuration
data OAuthConfig = OAuthConfig
    { oauthProvider :: OAuthProvider    -- Provider type
    , oauthClientId :: Text             -- Client ID
    , oauthClientSecret :: Text         -- Client secret
    , oauthRedirectUri :: Text          -- Redirect URI
    , oauthScopes :: [Text]             -- Required scopes
    , oauthAuthEndpoint :: Text         -- Authorization endpoint
    , oauthTokenEndpoint :: Text        -- Token endpoint
    , oauthUserInfoEndpoint :: Text     -- User info endpoint
    , oauthPKCE :: Bool                 -- Enable PKCE
    , oauthRoleMapping :: Map Text Text -- Role mapping rules
    } deriving (Show, Eq, Generic)

-- | OAuth provider types
data OAuthProvider
    = GitHub
    | GitLab
    | Google
    | Microsoft
    | Custom Text                       -- Custom provider name
    deriving (Show, Eq, Generic)

-- | Authentication result
data AuthResult
    = AuthSuccess AuthToken User
    | AuthFailure AuthError
    | AuthChallenge Challenge
    deriving (Show, Eq, Generic)

-- | Authentication token
data AuthToken = AuthToken
    { tokenValue :: Text
    , tokenType :: TokenType
    , tokenExpiry :: UTCTime
    , tokenScopes :: [Text]
    , tokenCSRFToken :: Maybe Text  -- Add CSRF token field
    } deriving (Show, Eq, Generic)

-- | Token types
data TokenType
    = BearerToken
    | JWTToken
    | APIToken
    deriving (Show, Eq, Generic)

-- | Authentication errors
data AuthError
    = InvalidCredentials
    | AccountLocked
    | AccountDisabled
    | ServerError Text
    | ConfigurationError Text
    | TokenExpired
    | InvalidToken
    | InsufficientPermissions
    deriving (Show, Eq, Generic)

instance Exception AuthError

-- | Authentication challenges
data Challenge
    = MFARequired Text    -- MFA token required
    | NewPasswordRequired -- Password change required
    | CaptchaRequired Text -- Captcha challenge
    deriving (Show, Eq, Generic)

-- | User information
data User = User
    { userId :: Text
    , userName :: Text
    , userEmail :: Text
    , userFullName :: Text
    , userRoles :: [Role]
    , userGroups :: [Text]
    , userProvider :: AuthProvider
    , userCreated :: UTCTime
    , userLastLogin :: UTCTime
    , userMFAEnabled :: Bool
    } deriving (Show, Eq, Generic)

-- | User roles
data Role
    = Admin
    | ProjectOwner
    | Developer
    | Reviewer
    | Guest
    deriving (Show, Eq, Generic)

-- | Permissions
data Permission
    = CreateProject
    | DeleteProject
    | ModifyProject
    | CreateBranch
    | DeleteBranch
    | Push
    | ForcePush
    | CreateTag
    | DeleteTag
    | Submit
    | Read
    deriving (Show, Eq, Generic)
