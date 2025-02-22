-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gerrit.Api.Types where

import Control.Lens
import Data.Aeson
import Data.Swagger
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)
import Servant.API
import Web.HttpApiData
import Gerrit.Models.Types (ReviewStatus, VoteValue)
import Gerrit.Models.Change (ChangeStatus)
import Gerrit.Models.Comment (CommentType)

-- | API types for requests and responses

data CreateProjectRequest = CreateProjectRequest
    { cprName :: Text
    , cprDescription :: Maybe Text
    } deriving (Show, Generic)

instance ToJSON CreateProjectRequest
instance FromJSON CreateProjectRequest

data CreateChangeRequest = CreateChangeRequest
    { ccrProject :: Text
    , ccrBranch :: Text
    , ccrSubject :: Text
    , ccrMessage :: Text
    } deriving (Show, Generic)

instance ToJSON CreateChangeRequest
instance FromJSON CreateChangeRequest

data ChangeInfo = ChangeInfo
    { ciId :: Text
    , ciProject :: Text
    , ciBranch :: Text
    , ciSubject :: Text
    , ciMessage :: Text
    , ciAuthor :: UserInfo
    , ciStatus :: ReviewStatus
    , ciCreatedAt :: UTCTime
    , ciUpdatedAt :: UTCTime
    , ciCurrentRevision :: Maybe RevisionInfo
    } deriving (Show, Generic)

instance ToJSON ChangeInfo
instance FromJSON ChangeInfo

-- | Core types with Swagger documentation
data RevisionInfo = RevisionInfo
    { riNumber :: Int
    , riCommitHash :: Text
    , riParentHash :: Text
    , riAuthor :: UserInfo
    , riCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON RevisionInfo
instance FromJSON RevisionInfo
instance ToSchema RevisionInfo where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Information about a change revision"
        & mapped.schema.example ?~ toJSON RevisionInfo
            { riNumber = 2
            , riCommitHash = "abc123def456"
            , riParentHash = "789ghi012"
            , riAuthor = UserInfo "user-123" "user@example.com" "John Doe"
            , riCreatedAt = read "2024-02-22 10:00:00 UTC"
            }

data UserInfo = UserInfo
    { uiId :: Text
    , uiEmail :: Text
    , uiName :: Text
    } deriving (Show, Generic)

instance ToJSON UserInfo
instance FromJSON UserInfo
instance ToSchema UserInfo where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Basic user information"
        & mapped.schema.example ?~ toJSON UserInfo
            { uiId = "user-123"
            , uiEmail = "user@example.com"
            , uiName = "John Doe"
            }

data LoginRequest = LoginRequest
    { loginEmail :: Text
    , loginPassword :: Text
    } deriving (Show, Generic)

instance ToJSON LoginRequest
instance FromJSON LoginRequest
instance ToSchema LoginRequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Login request with email and password"
        & mapped.schema.example ?~ toJSON LoginRequest
            { loginEmail = "user@example.com"
            , loginPassword = "password123"
            }

data TokenResponse = TokenResponse
    { tokenValue :: Text
    , tokenType :: Text
    , tokenExpiry :: UTCTime
    } deriving (Show, Generic)

instance ToJSON TokenResponse
instance FromJSON TokenResponse
instance ToSchema TokenResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Authentication token response"
        & mapped.schema.example ?~ toJSON TokenResponse
            { tokenValue = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
            , tokenType = "Bearer"
            , tokenExpiry = read "2024-03-22 10:00:00 UTC"
            }

data UpdateUserRequest = UpdateUserRequest
    { updateUserName :: Text
    , updateUserEmail :: Text
    , updateUserFullName :: Text
    , updateUserRoles :: [Text]
    , updateUserGroups :: [Text]
    , updateUserMFAEnabled :: Bool
    } deriving (Show, Generic)

instance ToJSON UpdateUserRequest
instance FromJSON UpdateUserRequest
instance ToSchema UpdateUserRequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Request to update user information"
        & mapped.schema.example ?~ toJSON UpdateUserRequest
            { updateUserName = "johndoe"
            , updateUserEmail = "john.doe@example.com"
            , updateUserFullName = "John Doe"
            , updateUserRoles = ["developer", "reviewer"]
            , updateUserGroups = ["team-a", "project-x"]
            , updateUserMFAEnabled = True
            }

data EnableMFARequest = EnableMFARequest
    { enableMFAType :: Text
    , enableMFAName :: Text
    } deriving (Show, Generic)

instance ToJSON EnableMFARequest
instance FromJSON EnableMFARequest
instance ToSchema EnableMFARequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Request to enable multi-factor authentication"
        & mapped.schema.example ?~ toJSON EnableMFARequest
            { enableMFAType = "totp"
            , enableMFAName = "Mobile Authenticator"
            }

data EnableMFAResponse = EnableMFAResponse
    { mfaSecret :: Text
    , mfaBackupCodes :: [Text]
    } deriving (Show, Generic)

instance ToJSON EnableMFAResponse
instance FromJSON EnableMFAResponse
instance ToSchema EnableMFAResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Response containing MFA setup information"
        & mapped.schema.example ?~ toJSON EnableMFAResponse
            { mfaSecret = "JBSWY3DPEHPK3PXP"
            , mfaBackupCodes = ["12345678", "87654321"]
            }

data VerifyMFARequest = VerifyMFARequest
    { verifyMFACode :: Text
    } deriving (Show, Generic)

instance ToJSON VerifyMFARequest
instance FromJSON VerifyMFARequest
instance ToSchema VerifyMFARequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Request to verify MFA code"
        & mapped.schema.example ?~ toJSON VerifyMFARequest
            { verifyMFACode = "123456"
            }

data VerifyMFAResponse = VerifyMFAResponse
    { verifyMFAValid :: Bool
    } deriving (Show, Generic)

instance ToJSON VerifyMFAResponse
instance FromJSON VerifyMFAResponse
instance ToSchema VerifyMFAResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Response indicating if MFA code is valid"
        & mapped.schema.example ?~ toJSON VerifyMFAResponse
            { verifyMFAValid = True
            }

data DisableMFARequest = DisableMFARequest
    { disableMFACode :: Text
    } deriving (Show, Generic)

instance ToJSON DisableMFARequest
instance FromJSON DisableMFARequest
instance ToSchema DisableMFARequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Request to disable MFA"
        & mapped.schema.example ?~ toJSON DisableMFARequest
            { disableMFACode = "123456"
            }

data BackupCodesResponse = BackupCodesResponse
    { backupCodes :: [Text]
    } deriving (Show, Generic)

instance ToJSON BackupCodesResponse
instance FromJSON BackupCodesResponse
instance ToSchema BackupCodesResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Response containing MFA backup codes"
        & mapped.schema.example ?~ toJSON BackupCodesResponse
            { backupCodes = ["12345678", "87654321", "23456789"]
            }

data SuccessResponse = SuccessResponse
    { success :: Bool
    } deriving (Show, Generic)

instance ToJSON SuccessResponse
instance FromJSON SuccessResponse
instance ToSchema SuccessResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Generic success response"
        & mapped.schema.example ?~ toJSON SuccessResponse
            { success = True
            }

data ErrorResponse = ErrorResponse
    { error :: Text
    } deriving (Show, Generic)

instance ToJSON ErrorResponse
instance FromJSON ErrorResponse
instance ToSchema ErrorResponse where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Error response with message"
        & mapped.schema.example ?~ toJSON ErrorResponse
            { error = "Invalid request parameters"
            }

-- | API type definitions using servant

type AuthHeader = Header "Authorization" Text

-- | Project API
type ProjectAPI =
    "projects" :>
        (    AuthHeader :> ReqBody '[JSON] CreateProjectRequest :> Post '[JSON] Text
        :<|> AuthHeader :> Capture "project" Text :> Get '[JSON] ProjectInfo
        :<|> AuthHeader :> Get '[JSON] [ProjectInfo]
        )

-- | Change API
type ChangeAPI =
    "changes" :> AuthProtect "jwt" :> (
        Summary "List changes" :>
        Description "Get list of all changes with optional filtering" :>
        QueryParam "project" Text :>
        QueryParam "branch" Text :>
        QueryParam "status" ReviewStatus :>
        QueryParam "author" Text :>
        QueryParam "reviewer" Text :>
        QueryParam "page" Int :>
        QueryParam "per_page" Int :>
        Get '[JSON] ChangeListResponse
        :<|>
        Summary "Create change" :>
        Description "Create a new change for code review" :>
        ReqBody '[JSON] CreateChangeRequest :>
        Post '[JSON] ChangeResponse
        :<|>
        Capture "id" Text :>
        Summary "Get change" :>
        Description "Get details of a specific change" :>
        Get '[JSON] ChangeResponse
        :<|>
        Capture "id" Text :> "revisions" :>
        Summary "List revisions" :>
        Description "Get list of all revisions for a change" :>
        Get '[JSON] [RevisionInfo]
        :<|>
        Capture "id" Text :> "submit" :>
        Summary "Submit change" :>
        Description "Submit a change for merging" :>
        Post '[JSON] NoContent
        )

-- | Comment API
type CommentAPI =
    "changes" :> Capture "change-id" Text :> "revisions" :> Capture "revision-id" Text :> "comments" :>
        (    AuthHeader :> ReqBody '[JSON] CommentInput :> Post '[JSON] ()
        :<|> AuthHeader :> Get '[JSON] [CommentInfo]
        )

-- | Complete API
type GerritAPI = ProjectAPI :<|> ChangeAPI :<|> CommentAPI

-- Additional types needed for responses

data ProjectInfo = ProjectInfo
    { piName :: Text
    , piDescription :: Maybe Text
    , piOwner :: UserInfo
    , piCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON ProjectInfo
instance FromJSON ProjectInfo

data CommentInfo = CommentInfo
    { cmId :: Text
    , cmAuthor :: UserInfo
    , cmFilePath :: Maybe Text
    , cmLineNumber :: Maybe Int
    , cmMessage :: Text
    , cmCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON CommentInfo
instance FromJSON CommentInfo

-- | Login request
data LoginRequest = LoginRequest
    { loginUsername :: Text
    , loginPassword :: Text
    } deriving (Show, Generic)

instance FromJSON LoginRequest
instance ToJSON LoginRequest

-- | Token response
data TokenResponse = TokenResponse
    { tokenValue :: Text
    , tokenType :: Text
    , tokenExpiry :: UTCTime
    } deriving (Show, Generic)

instance FromJSON TokenResponse
instance ToJSON TokenResponse

-- | User response
data UserResponse = UserResponse
    { userId :: Text
    , userName :: Text
    , userEmail :: Text
    , userFullName :: Text
    , userRoles :: [Text]
    , userGroups :: [Text]
    , userMFAEnabled :: Bool
    , userCreatedAt :: UTCTime
    , userUpdatedAt :: UTCTime
    } deriving (Show, Generic)

instance FromJSON UserResponse
instance ToJSON UserResponse

-- | Update user request
data UpdateUserRequest = UpdateUserRequest
    { updateUserName :: Text
    , updateUserEmail :: Text
    , updateUserFullName :: Text
    , updateUserRoles :: [Text]
    , updateUserGroups :: [Text]
    , updateUserMFAEnabled :: Bool
    } deriving (Show, Generic)

instance FromJSON UpdateUserRequest
instance ToJSON UpdateUserRequest

-- | Enable MFA request
data EnableMFARequest = EnableMFARequest
    { enableMFAType :: Text
    , enableMFAName :: Text
    } deriving (Show, Generic)

instance FromJSON EnableMFARequest
instance ToJSON EnableMFARequest

-- | Enable MFA response
data EnableMFAResponse = EnableMFAResponse
    { mfaSecret :: Text
    , mfaBackupCodes :: [Text]
    } deriving (Show, Generic)

instance FromJSON EnableMFAResponse
instance ToJSON EnableMFAResponse

-- | Verify MFA request
data VerifyMFARequest = VerifyMFARequest
    { verifyMFACode :: Text
    } deriving (Show, Generic)

instance FromJSON VerifyMFARequest
instance ToJSON VerifyMFARequest

-- | Verify MFA response
data VerifyMFAResponse = VerifyMFAResponse
    { verifyMFAValid :: Bool
    } deriving (Show, Generic)

instance FromJSON VerifyMFAResponse
instance ToJSON VerifyMFAResponse

-- | Disable MFA request
data DisableMFARequest = DisableMFARequest
    { disableMFACode :: Text
    } deriving (Show, Generic)

instance FromJSON DisableMFARequest
instance ToJSON DisableMFARequest

-- | Backup codes response
data BackupCodesResponse = BackupCodesResponse
    { backupCodes :: [Text]
    } deriving (Show, Generic)

instance FromJSON BackupCodesResponse
instance ToJSON BackupCodesResponse

-- | Success response
data SuccessResponse = SuccessResponse
    { success :: Bool
    } deriving (Show, Generic)

instance FromJSON SuccessResponse
instance ToJSON SuccessResponse

-- | Error response
data ErrorResponse = ErrorResponse
    { error :: Text
    } deriving (Show, Generic)

instance FromJSON ErrorResponse
instance ToJSON ErrorResponse

-- | Complete API type combining all endpoints
type API = AuthAPI :<|> ProjectAPI :<|> ReviewAPI :<|> BillingAPI

-- | Authentication API endpoints
type AuthAPI =
    "auth" :> (
        "register" :>
            Summary "Register new user" :>
            Description "Create a new user account with email and password" :>
            ReqBody '[JSON] RegisterRequest :>
            Post '[JSON] AuthResponse
        :<|>
        "login" :>
            Summary "User login" :>
            Description "Authenticate user and get JWT token" :>
            ReqBody '[JSON] LoginRequest :>
            Post '[JSON] AuthResponse
        :<|>
        "logout" :>
            Summary "User logout" :>
            Description "Invalidate current JWT token" :>
            AuthProtect "jwt" :>
            Post '[JSON] NoContent
        :<|>
        "me" :>
            Summary "Get current user" :>
            Description "Get details of currently authenticated user" :>
            AuthProtect "jwt" :>
            Get '[JSON] UserResponse
        :<|>
        "mfa" :> (
            "enable" :>
                Summary "Enable MFA" :>
                Description "Enable multi-factor authentication for user" :>
                AuthProtect "jwt" :>
                ReqBody '[JSON] EnableMFARequest :>
                Post '[JSON] EnableMFAResponse
            :<|>
            "disable" :>
                Summary "Disable MFA" :>
                Description "Disable multi-factor authentication for user" :>
                AuthProtect "jwt" :>
                ReqBody '[JSON] DisableMFARequest :>
                Post '[JSON] NoContent
            :<|>
            "verify" :>
                Summary "Verify MFA code" :>
                Description "Verify MFA code during login" :>
                ReqBody '[JSON] VerifyMFARequest :>
                Post '[JSON] VerifyMFAResponse
        )
    )

-- | Project management API endpoints
type ProjectAPI =
    "projects" :> AuthProtect "jwt" :> (
        Summary "List projects" :>
        Description "Get list of all accessible projects" :>
        QueryParam "page" Int :>
        QueryParam "per_page" Int :>
        Get '[JSON] ProjectListResponse
        :<|>
        Summary "Create project" :>
        Description "Create a new project" :>
        ReqBody '[JSON] CreateProjectRequest :>
        Post '[JSON] ProjectResponse
        :<|>
        Capture "id" Text :>
        Summary "Get project" :>
        Description "Get details of a specific project" :>
        Get '[JSON] ProjectResponse
        :<|>
        Capture "id" Text :>
        Summary "Update project" :>
        Description "Update project details" :>
        ReqBody '[JSON] UpdateProjectRequest :>
        Put '[JSON] ProjectResponse
        :<|>
        Capture "id" Text :>
        Summary "Delete project" :>
        Description "Delete a project" :>
        Delete '[JSON] NoContent
    )

-- | Review API endpoints
type ReviewAPI =
    "changes" :> AuthProtect "jwt" :> (
        Get '[JSON] ChangeListResponse :<|>
        ReqBody '[JSON] CreateChangeRequest :> Post '[JSON] ChangeResponse :<|>
        Capture "id" Text :> Get '[JSON] ChangeResponse
    )

-- | Billing API endpoints
type BillingAPI =
    "billing" :> AuthProtect "jwt" :> (
        "plans" :>
            Summary "List billing plans" :>
            Description "Get list of available billing plans" :>
            Get '[JSON] PlanListResponse
        :<|>
        "coupons" :>
            Summary "List coupons" :>
            Description "Get list of available coupons" :>
            Get '[JSON] CouponListResponse
        :<|>
        "enterprises" :> Capture "id" Text :> (
            "billing" :>
                Summary "Get enterprise billing" :>
                Description "Get billing information for an enterprise" :>
                Get '[JSON] EnterpriseBillingResponse
            :<|>
            "invoices" :>
                Summary "List invoices" :>
                Description "Get list of invoices for an enterprise" :>
                QueryParam "page" Int :>
                QueryParam "per_page" Int :>
                Get '[JSON] InvoiceListResponse
        )
    )

-- | Common response wrapper
data Response a = Response
    { success :: Bool
    , data_ :: a
    , audit :: Maybe AuditTrail
    , pagination :: Maybe PaginationInfo
    } deriving (Show, Eq, Generic)

instance ToJSON a => ToJSON (Response a)
instance FromJSON a => FromJSON (Response a)
instance ToSchema a => ToSchema (Response a)

-- | Pagination information
data PaginationInfo = PaginationInfo
    { total :: Int
    , perPage :: Int
    , currentPage :: Int
    , lastPage :: Int
    } deriving (Show, Generic)

instance ToJSON PaginationInfo
instance FromJSON PaginationInfo
instance ToSchema PaginationInfo

-- | Authentication requests/responses
data RegisterRequest = RegisterRequest
    { registerEmail :: Text
    , registerPassword :: Text
    , registerName :: Text
    } deriving (Show, Generic)

instance ToJSON RegisterRequest
instance FromJSON RegisterRequest
instance ToSchema RegisterRequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "User registration request"
        & mapped.schema.example ?~ toJSON (RegisterRequest "user@example.com" "password123" "John Doe")

data AuthResponse = AuthResponse
    { authToken :: Text
    , authUser :: UserResponse
    } deriving (Show, Generic)

instance ToJSON AuthResponse
instance FromJSON AuthResponse
instance ToSchema AuthResponse

-- | User response
data UserResponse = UserResponse
    { userId :: Text
    , userEmail :: Text
    , userName :: Text
    , userRole :: Text
    } deriving (Show, Generic)

instance ToJSON UserResponse
instance FromJSON UserResponse

-- | Project requests/responses
data CreateProjectRequest = CreateProjectRequest
    { createProjectName :: Text
    , createProjectDescription :: Maybe Text
    } deriving (Show, Generic)

instance ToJSON CreateProjectRequest
instance FromJSON CreateProjectRequest
instance ToSchema CreateProjectRequest

type ProjectListResponse = Response [ProjectResponse]
type ProjectResponse = Response Project

-- | Change requests/responses
data CreateChangeRequest = CreateChangeRequest
    { createChangeProjectId :: Text
    , createChangeBranch :: Text
    , createChangeSubject :: Text
    , createChangeDescription :: Text
    } deriving (Show, Generic)

instance ToJSON CreateChangeRequest
instance FromJSON CreateChangeRequest
instance ToSchema CreateChangeRequest

type ChangeListResponse = Response [ChangeResponse]
type ChangeResponse = Response Change

-- | Billing types
type PlanListResponse = Response [Plan]
type CouponListResponse = Response [Coupon]

-- | Change management API endpoints
type ChangeAPI =
    "changes" :> AuthProtect "jwt" :> (
        Summary "List changes" :>
        Description "Get list of all changes with optional filtering" :>
        QueryParam "project" Text :>
        QueryParam "branch" Text :>
        QueryParam "status" ReviewStatus :>
        QueryParam "author" Text :>
        QueryParam "reviewer" Text :>
        QueryParam "page" Int :>
        QueryParam "per_page" Int :>
        Get '[JSON] ChangeListResponse
        :<|>
        Summary "Create change" :>
        Description "Create a new change for code review" :>
        ReqBody '[JSON] CreateChangeRequest :>
        Post '[JSON] ChangeResponse
        :<|>
        Capture "id" Text :>
        Summary "Get change" :>
        Description "Get details of a specific change" :>
        Get '[JSON] ChangeResponse
        :<|>
        Capture "id" Text :> "revisions" :>
        Summary "List revisions" :>
        Description "Get list of all revisions for a change" :>
        Get '[JSON] [RevisionInfo]
        :<|>
        Capture "id" Text :> "submit" :>
        Summary "Submit change" :>
        Description "Submit a change for merging" :>
        Post '[JSON] NoContent
    )

-- | Review management API endpoints
type ReviewAPI =
    "changes" :> Capture "id" Text :> "revisions" :> Capture "revision" Text :> (
        "review" :>
            Summary "Submit review" :>
            Description "Submit a review with comments and vote" :>
            AuthProtect "jwt" :>
            ReqBody '[JSON] ReviewInput :>
            Post '[JSON] NoContent
        :<|>
        "comments" :>
            Summary "List comments" :>
            Description "Get all comments for a revision" :>
            AuthProtect "jwt" :>
            Get '[JSON] [CommentInfo]
        :<|>
        "comments" :>
            Summary "Create comment" :>
            Description "Create a new comment on a revision" :>
            AuthProtect "jwt" :>
            ReqBody '[JSON] CommentInput :>
            Post '[JSON] CommentInfo
    )

-- | Change types with Swagger documentation
data CreateChangeRequest = CreateChangeRequest
    { ccrProject :: Text
    , ccrBranch :: Text
    , ccrSubject :: Text
    , ccrMessage :: Text
    } deriving (Show, Generic)

instance ToJSON CreateChangeRequest
instance FromJSON CreateChangeRequest
instance ToSchema CreateChangeRequest where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Create change request"
        & mapped.schema.example ?~ toJSON CreateChangeRequest
            { ccrProject = "my-project"
            , ccrBranch = "feature/new-feature"
            , ccrSubject = "Add new feature"
            , ccrMessage = "Implement new feature with the following changes:\n\n- Add feature A\n- Update tests\n- Update documentation"
            }

data ChangeInfo = ChangeInfo
    { ciId :: Text
    , ciProject :: Text
    , ciBranch :: Text
    , ciSubject :: Text
    , ciMessage :: Text
    , ciAuthor :: UserInfo
    , ciStatus :: ReviewStatus
    , ciCreatedAt :: UTCTime
    , ciUpdatedAt :: UTCTime
    , ciCurrentRevision :: Maybe RevisionInfo
    } deriving (Show, Generic)

instance ToJSON ChangeInfo
instance FromJSON ChangeInfo
instance ToSchema ChangeInfo where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Change information"
        & mapped.schema.example ?~ toJSON (ChangeInfo
            "change-123"
            "my-project"
            "feature/new-feature"
            "Add new feature"
            "Implement new feature"
            (UserInfo "user-123" "user@example.com" "John Doe")
            ReviewInProgress
            (read "2024-02-22 10:00:00 UTC")
            (read "2024-02-22 10:00:00 UTC")
            Nothing)

-- | Review types with Swagger documentation
data ReviewInput = ReviewInput
    { riMessage :: Maybe Text
    , riVote :: VoteValue
    , riComments :: [CommentInput]
    } deriving (Show, Generic)

instance ToJSON ReviewInput
instance FromJSON ReviewInput
instance ToSchema ReviewInput where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Review input with comments and vote"
        & mapped.schema.example ?~ toJSON ReviewInput
            { riMessage = Just "Looks good, but needs some minor fixes"
            , riVote = VoteApproved
            , riComments = [CommentInput
                (Just "src/main.rs")
                (Just 42)
                "Consider using a more descriptive variable name"]
            }

data CommentInput = CommentInput
    { ciFilePath :: Maybe Text
    , ciLineNumber :: Maybe Int
    , ciMessage :: Text
    } deriving (Show, Generic)

instance ToJSON CommentInput
instance FromJSON CommentInput
instance ToSchema CommentInput where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Comment input for code review"
        & mapped.schema.example ?~ toJSON CommentInput
            { ciFilePath = Just "src/main.rs"
            , ciLineNumber = Just 42
            , ciMessage = "Consider using a more descriptive variable name"
            }

data CommentInfo = CommentInfo
    { cmId :: Text
    , cmAuthor :: UserInfo
    , cmFilePath :: Maybe Text
    , cmLineNumber :: Maybe Int
    , cmMessage :: Text
    , cmCreatedAt :: UTCTime
    } deriving (Show, Generic)

instance ToJSON CommentInfo
instance FromJSON CommentInfo
instance ToSchema CommentInfo where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Comment information"
        & mapped.schema.example ?~ toJSON CommentInfo
            { cmId = "comment-123"
            , cmAuthor = UserInfo "user-123" "user@example.com" "John Doe"
            , cmFilePath = Just "src/main.rs"
            , cmLineNumber = Just 42
            , cmMessage = "Consider using a more descriptive variable name"
            , cmCreatedAt = read "2024-02-22 10:00:00 UTC"
            }

-- | Billing types with Swagger documentation
data Plan = Plan
    { planId :: Text
    , planName :: Text
    , planDescription :: Text
    , planPrice :: Double
    , planInterval :: Text
    , planFeatures :: [Text]
    } deriving (Show, Generic)

instance ToJSON Plan
instance FromJSON Plan
instance ToSchema Plan where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Billing plan information"
        & mapped.schema.example ?~ toJSON Plan
            { planId = "plan-enterprise"
            , planName = "Enterprise"
            , planDescription = "Enterprise plan with advanced features"
            , planPrice = 99.99
            , planInterval = "monthly"
            , planFeatures = ["Unlimited users", "Priority support", "Custom integrations"]
            }

data Coupon = Coupon
    { couponCode :: Text
    , couponDescription :: Text
    , couponDiscount :: Double
    , couponType :: Text
    , couponValidUntil :: UTCTime
    } deriving (Show, Generic)

instance ToJSON Coupon
instance FromJSON Coupon
instance ToSchema Coupon where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Coupon information"
        & mapped.schema.example ?~ toJSON Coupon
            { couponCode = "WELCOME2024"
            , couponDescription = "Welcome discount for new users"
            , couponDiscount = 20.0
            , couponType = "percentage"
            , couponValidUntil = read "2024-12-31 23:59:59 UTC"
            }

data EnterpriseBilling = EnterpriseBilling
    { ebPlan :: Plan
    , ebNextBillingDate :: UTCTime
    , ebActiveUsers :: Int
    , ebTotalSeats :: Int
    , ebCurrentCharges :: Double
    } deriving (Show, Generic)

instance ToJSON EnterpriseBilling
instance FromJSON EnterpriseBilling
instance ToSchema EnterpriseBilling where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Enterprise billing information"
        & mapped.schema.example ?~ toJSON EnterpriseBilling
            { ebPlan = Plan "plan-enterprise" "Enterprise" "Enterprise plan" 99.99 "monthly" []
            , ebNextBillingDate = read "2024-03-22 00:00:00 UTC"
            , ebActiveUsers = 25
            , ebTotalSeats = 50
            , ebCurrentCharges = 2499.75
            }

data Invoice = Invoice
    { invoiceId :: Text
    , invoiceNumber :: Text
    , invoiceDate :: UTCTime
    , invoiceDueDate :: UTCTime
    , invoiceAmount :: Double
    , invoiceStatus :: Text
    , invoiceItems :: [InvoiceItem]
    } deriving (Show, Generic)

instance ToJSON Invoice
instance FromJSON Invoice
instance ToSchema Invoice where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Invoice information"
        & mapped.schema.example ?~ toJSON Invoice
            { invoiceId = "inv-123"
            , invoiceNumber = "INV-2024-001"
            , invoiceDate = read "2024-02-22 00:00:00 UTC"
            , invoiceDueDate = read "2024-03-22 00:00:00 UTC"
            , invoiceAmount = 2499.75
            , invoiceStatus = "paid"
            , invoiceItems = [InvoiceItem "Enterprise Plan - Monthly" 1 2499.75 2499.75]
            }

data InvoiceItem = InvoiceItem
    { iiDescription :: Text
    , iiQuantity :: Int
    , iiUnitPrice :: Double
    , iiAmount :: Double
    } deriving (Show, Generic)

instance ToJSON InvoiceItem
instance FromJSON InvoiceItem
instance ToSchema InvoiceItem where
    declareNamedSchema proxy = genericDeclareNamedSchema defaultSchemaOptions proxy
        & mapped.schema.description ?~ "Invoice line item"
        & mapped.schema.example ?~ toJSON (InvoiceItem
            "Enterprise Plan - Monthly"
            1
            2499.75
            2499.75)

-- Type aliases for responses
type ProjectListResponse = Response [ProjectResponse]
type ProjectResponse = Response Project
type ChangeListResponse = Response [ChangeResponse]
type ChangeResponse = Response Change
type PlanListResponse = Response [Plan]
type CouponListResponse = Response [Coupon]
type InvoiceListResponse = Response [Invoice]
type EnterpriseBillingResponse = Response EnterpriseBilling

-- | Audit trail information for operations
data AuditTrail = AuditTrail
    { auditId :: Text
    , timestamp :: UTCTime
    , actor :: Text
    , action :: Text
    , resource :: Text
    , details :: Value
    , ipAddress :: Maybe Text
    , userAgent :: Maybe Text
    } deriving (Show, Eq, Generic)

instance ToJSON AuditTrail
instance FromJSON AuditTrail
instance ToSchema AuditTrail where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Audit trail information for API operations"
                & properties .~ props
                & required .~ ["auditId", "timestamp", "actor", "action", "resource", "details"]
        pure $ NamedSchema (Just "AuditTrail") schema
      where
        props = mempty
            & at "auditId" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "Unique identifier for the audit entry")
            & at "timestamp" ?~ (mempty
                & type_ ?~ SwaggerString
                & format ?~ "date-time"
                & description ?~ "When the operation occurred")
            & at "actor" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "User or system that performed the action")
            & at "action" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "Type of operation performed")
            & at "resource" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "Resource that was affected")
            & at "details" ?~ (mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Additional context about the operation")
            & at "ipAddress" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "IP address of the actor")
            & at "userAgent" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "User agent of the actor")

-- | Enhanced authentication response with MFA status
data AuthResponse = AuthResponse
    { token :: Text
    , expiresAt :: UTCTime
    , mfaEnabled :: Bool
    , mfaVerified :: Bool
    , backupCodesRemaining :: Maybe Int
    } deriving (Show, Eq, Generic)

instance ToJSON AuthResponse
instance FromJSON AuthResponse
instance ToSchema AuthResponse where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Authentication response with MFA status"
                & properties .~ props
                & required .~ ["token", "expiresAt", "mfaEnabled", "mfaVerified"]
        pure $ NamedSchema (Just "AuthResponse") schema
      where
        props = mempty
            & at "token" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "JWT authentication token")
            & at "expiresAt" ?~ (mempty
                & type_ ?~ SwaggerString
                & format ?~ "date-time"
                & description ?~ "Token expiration timestamp")
            & at "mfaEnabled" ?~ (mempty
                & type_ ?~ SwaggerBoolean
                & description ?~ "Whether MFA is enabled for the account")
            & at "mfaVerified" ?~ (mempty
                & type_ ?~ SwaggerBoolean
                & description ?~ "Whether MFA has been verified for this session")
            & at "backupCodesRemaining" ?~ (mempty
                & type_ ?~ SwaggerInteger
                & description ?~ "Number of backup codes remaining")

-- | MFA setup request
data EnableMFARequest = EnableMFARequest
    { mfaType :: Text  -- ^ Type of MFA (totp, sms, etc)
    , phoneNumber :: Maybe Text  -- ^ Phone number for SMS
    } deriving (Show, Eq, Generic)

instance ToJSON EnableMFARequest
instance FromJSON EnableMFARequest
instance ToSchema EnableMFARequest where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Request to enable multi-factor authentication"
                & properties .~ props
                & required .~ ["mfaType"]
        pure $ NamedSchema (Just "EnableMFARequest") schema
      where
        props = mempty
            & at "mfaType" ?~ (mempty
                & type_ ?~ SwaggerString
                & enum_ ?~ ["totp", "sms"]
                & description ?~ "Type of MFA to enable")
            & at "phoneNumber" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "Phone number for SMS authentication")

-- | MFA setup response
data EnableMFAResponse = EnableMFAResponse
    { secret :: Text  -- ^ TOTP secret
    , qrCode :: Text  -- ^ QR code data URL
    , backupCodes :: [Text]  -- ^ List of backup codes
    } deriving (Show, Eq, Generic)

instance ToJSON EnableMFAResponse
instance FromJSON EnableMFAResponse
instance ToSchema EnableMFAResponse where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Response containing MFA setup information"
                & properties .~ props
                & required .~ ["secret", "qrCode", "backupCodes"]
        pure $ NamedSchema (Just "EnableMFAResponse") schema
      where
        props = mempty
            & at "secret" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "TOTP secret key")
            & at "qrCode" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "QR code as a data URL")
            & at "backupCodes" ?~ (mempty
                & type_ ?~ SwaggerArray
                & items ?~ SwaggerItemsObject (mempty
                    & type_ ?~ SwaggerString)
                & description ?~ "List of backup codes")

-- | MFA verification request
data VerifyMFARequest = VerifyMFARequest
    { code :: Text  -- ^ TOTP code or backup code
    } deriving (Show, Eq, Generic)

instance ToJSON VerifyMFARequest
instance FromJSON VerifyMFARequest
instance ToSchema VerifyMFARequest where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Request to verify MFA code"
                & properties .~ props
                & required .~ ["code"]
        pure $ NamedSchema (Just "VerifyMFARequest") schema
      where
        props = mempty
            & at "code" ?~ (mempty
                & type_ ?~ SwaggerString
                & description ?~ "TOTP code or backup code")

-- | MFA verification response
data VerifyMFAResponse = VerifyMFAResponse
    { verified :: Bool
    , remainingAttempts :: Maybe Int
    } deriving (Show, Eq, Generic)

instance ToJSON VerifyMFAResponse
instance FromJSON VerifyMFAResponse
instance ToSchema VerifyMFAResponse where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Response for MFA verification"
                & properties .~ props
                & required .~ ["verified"]
        pure $ NamedSchema (Just "VerifyMFAResponse") schema
      where
        props = mempty
            & at "verified" ?~ (mempty
                & type_ ?~ SwaggerBoolean
                & description ?~ "Whether the code was valid")
            & at "remainingAttempts" ?~ (mempty
                & type_ ?~ SwaggerInteger
                & description ?~ "Number of attempts remaining before lockout")

-- | Standard response wrapper with audit trail
data Response a = Response
    { success :: Bool
    , data_ :: a
    , audit :: Maybe AuditTrail
    , pagination :: Maybe PaginationInfo
    } deriving (Show, Eq, Generic)

instance ToJSON a => ToJSON (Response a)
instance FromJSON a => FromJSON (Response a)
instance ToSchema a => ToSchema (Response a) where
    declareNamedSchema proxy = do
        let schema = mempty
                & type_ ?~ SwaggerObject
                & description ?~ "Standard response wrapper with audit trail"
                & properties .~ props
                & required .~ ["success", "data"]
        pure $ NamedSchema (Just "Response") schema
      where
        props = mempty
            & at "success" ?~ (mempty
                & type_ ?~ SwaggerBoolean
                & description ?~ "Whether the operation was successful")
            & at "data" ?~ (mempty
                & description ?~ "Response data")
            & at "audit" ?~ (mempty
                & description ?~ "Audit trail information if requested")
            & at "pagination" ?~ (mempty
                & description ?~ "Pagination information for list endpoints")
