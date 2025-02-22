-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- | Module for serving OpenAPI/Swagger documentation
module Gerrit.Web.Docs
    ( SwaggerAPI
    , swaggerServer
    , swaggerUIServer
    ) where

import Control.Lens
import Data.Aeson (toJSON)
import Data.Swagger
import Data.Text (Text)
import Network.Wai.Handler.Warp (Port)
import Servant
import Servant.Swagger
import Servant.Swagger.UI
import qualified Data.ByteString.Lazy as BL
import qualified Data.HashMap.Strict.InsOrd as HM

import Gerrit.Api.Types
import Gerrit.Auth.Types
import Gerrit.Models.Types

-- | API type for Swagger documentation endpoints
type SwaggerAPI =
    "api" :> "docs" :> "openapi.json" :> Get '[JSON] Swagger
    :<|> "api" :> "docs" :> SwaggerSchemaUI "swagger-ui" "openapi.json"

-- | Generate OpenAPI specification
generateSwagger :: Swagger
generateSwagger = toSwagger (Proxy :: Proxy API)
    & info.title .~ "Gerrit API"
    & info.version .~ "1.0"
    & info.description ?~ apiDescription
    & info.license ?~ ("Proprietary" & url ?~ URL "https://ghuntley.com")
    & info.contact ?~ Contact
        (Just "Geoffrey Huntley")
        (Just $ URL "https://ghuntley.com")
        (Just "ghuntley@ghuntley.com")
    & securityDefinitions .~ securitySchemes
    & security .~ [SecurityRequirement [("jwt", []), ("oauth2", ["read", "write"])]]
    & tags .~ apiTags
    & components.schemas %~ addCommonSchemas
    & components.parameters %~ addCommonParameters
    & components.responses %~ addCommonResponses
    & components.securitySchemes %~ addSecuritySchemes
    & externalDocs ?~ ExternalDocs
        "Additional Documentation"
        (URL "https://docs.ghuntley.com/gerrit")

-- | Security schemes for authentication
securitySchemes :: SecurityDefinitions
securitySchemes = SecurityDefinitions $ HM.fromList
    [ ("jwt", SecurityScheme "jwt" "JWT Authentication" $
        ApiKeyParams "Authorization" ApiKeyHeader)
    , ("oauth2", SecurityScheme "oauth2" "OAuth2 Authentication" $
        OAuth2Params
            [ AuthorizationCodeFlow
                (URL "https://auth.ghuntley.com/oauth/authorize")
                (Just $ URL "https://auth.ghuntley.com/oauth/token")
                Nothing
            ]
            ["read", "write"]
            Nothing)
    , ("ldap", SecurityScheme "ldap" "LDAP Authentication" $
        BasicAuthParams Nothing)
    ]

-- | API tags for grouping endpoints
apiTags :: [Tag]
apiTags =
    [ Tag "Authentication" (Just "User authentication and authorization")
    , Tag "Projects" (Just "Project management")
    , Tag "Changes" (Just "Change management")
    , Tag "Reviews" (Just "Code review operations")
    , Tag "Billing" (Just "Billing and subscription management")
    , Tag "Organizations" (Just "Organization and team management")
    , Tag "Stacks" (Just "Change stack operations")
    , Tag "Merge Queue" (Just "Merge queue management")
    , Tag "Audit" (Just "Audit logging and tracking")
    ]

-- | API description with detailed information
apiDescription :: Text
apiDescription = mconcat
    [ "# Gerrit API Documentation\n\n"
    , "The Gerrit API provides programmatic access to the code review system. "
    , "It follows REST principles and uses JSON for request and response bodies.\n\n"
    , "## Authentication\n\n"
    , "The API supports multiple authentication methods:\n\n"
    , "1. **JWT Authentication**\n"
    , "   - Required for most endpoints\n"
    , "   - Format: `Authorization: Bearer <token>`\n"
    , "   - Obtain via `/api/auth/login` endpoint\n\n"
    , "2. **OAuth2 Authentication**\n"
    , "   - Supported providers: GitHub, GitLab, Google, Microsoft\n"
    , "   - Authorization code flow with PKCE\n"
    , "   - Scopes: read, write\n\n"
    , "3. **LDAP Authentication**\n"
    , "   - Enterprise LDAP/Active Directory integration\n"
    , "   - Group synchronization\n"
    , "   - Role mapping\n\n"
    , "## Security Features\n\n"
    , "1. **Multi-Factor Authentication (MFA)**\n"
    , "   - TOTP support\n"
    , "   - Backup codes\n"
    , "   - Device management\n\n"
    , "2. **Rate Limiting**\n"
    , "   - Authentication endpoints: 10 requests/minute\n"
    , "   - API endpoints: 60 requests/minute/user\n"
    , "   - Webhook endpoints: 120 requests/minute/organization\n\n"
    , "3. **Audit Logging**\n"
    , "   - All operations are logged\n"
    , "   - Includes actor, action, resource, context\n"
    , "   - Enterprise-specific audit trails\n\n"
    , "## Pagination\n\n"
    , "List endpoints support pagination using query parameters:\n"
    , "- `page`: Page number (default: 1)\n"
    , "- `per_page`: Items per page (default: 20, max: 100)\n\n"
    , "Response includes pagination metadata:\n"
    , "```json\n"
    , "{\n"
    , "    \"success\": true,\n"
    , "    \"data\": [...],\n"
    , "    \"pagination\": {\n"
    , "        \"total\": 100,\n"
    , "        \"per_page\": 20,\n"
    , "        \"current_page\": 1,\n"
    , "        \"last_page\": 5\n"
    , "    }\n"
    , "}\n"
    , "```\n\n"
    , "## Error Handling\n\n"
    , "Error responses follow a standard format:\n"
    , "```json\n"
    , "{\n"
    , "    \"success\": false,\n"
    , "    \"error\": {\n"
    , "        \"code\": \"ERROR_CODE\",\n"
    , "        \"message\": \"Human readable error message\"\n"
    , "    }\n"
    , "}\n"
    , "```\n\n"
    , "Common error codes:\n"
    , "- `INVALID_REQUEST`: Invalid request parameters\n"
    , "- `UNAUTHORIZED`: Authentication required\n"
    , "- `FORBIDDEN`: Permission denied\n"
    , "- `NOT_FOUND`: Resource not found\n"
    , "- `RATE_LIMITED`: Rate limit exceeded\n"
    , "- `VALIDATION_ERROR`: Request validation failed\n"
    , "- `INTERNAL_ERROR`: Internal server error\n\n"
    , "## API Versioning\n\n"
    , "The API is versioned through the URL path. The current version is v1.\n"
    , "Breaking changes will only be introduced in new API versions.\n\n"
    , "## SDK Support\n\n"
    , "Official SDKs are available for:\n"
    , "- TypeScript/JavaScript\n"
    , "- Python\n"
    , "- Go\n"
    , "- Java\n"
    , "- Ruby\n\n"
    , "Generate SDKs using openapi-generator:\n"
    , "```bash\n"
    , "openapi-generator generate -i /api/docs/openapi.json -g <language>\n"
    , "```\n"
    ]

-- | Add security schemes
addSecuritySchemes :: HM.InsOrdHashMap Text SecurityScheme -> HM.InsOrdHashMap Text SecurityScheme
addSecuritySchemes schemes = schemes <> HM.fromList
    [ ("jwt", SecurityScheme "jwt" "JWT Authentication" $
        ApiKeyParams "Authorization" ApiKeyHeader)
    , ("oauth2", SecurityScheme "oauth2" "OAuth2 Authentication" $
        OAuth2Params
            [ AuthorizationCodeFlow
                (URL "https://auth.ghuntley.com/oauth/authorize")
                (Just $ URL "https://auth.ghuntley.com/oauth/token")
                Nothing
            ]
            ["read", "write"]
            Nothing)
    , ("ldap", SecurityScheme "ldap" "LDAP Authentication" $
        BasicAuthParams Nothing)
    ]

-- | Add common parameters used across endpoints
addCommonParameters :: HM.InsOrdHashMap Text Parameter -> HM.InsOrdHashMap Text Parameter
addCommonParameters params = params <> HM.fromList
    [ ("page", pageParam)
    , ("per_page", perPageParam)
    , ("sort", sortParam)
    , ("order", orderParam)
    , ("q", searchParam)
    , ("enterprise_id", enterpriseParam)
    , ("include_audit", auditParam)
    ]
  where
    enterpriseParam = mempty
        & in_ .~ ParamHeader
        & name .~ "X-Enterprise-ID"
        & description ?~ "Enterprise ID for multi-tenant isolation"
        & required ?~ True
        & schema .~ ParamOther (mempty & type_ ?~ SwaggerString)

    auditParam = mempty
        & in_ .~ ParamQuery
        & name .~ "include_audit"
        & description ?~ "Include audit trail in response"
        & required ?~ False
        & schema .~ ParamOther (mempty
            & type_ ?~ SwaggerBoolean
            & default_ ?~ toJSON False)

-- | Add common response types
addCommonResponses :: HM.InsOrdHashMap Text Response -> HM.InsOrdHashMap Text Response
addCommonResponses responses = responses <> HM.fromList
    [ ("UnauthorizedError", unauthorizedResponse)
    , ("ValidationError", validationResponse)
    , ("NotFoundError", notFoundResponse)
    , ("RateLimitError", rateLimitResponse)
    , ("InternalError", internalErrorResponse)
    , ("AuditResponse", auditResponse)
    ]
  where
    auditResponse = mempty
        & description .~ "Operation audit trail"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "AuditTrail"))
        & headers .~ HM.fromList
            [ ("X-Audit-ID", Header "X-Audit-ID" (mempty & type_ ?~ SwaggerString))
            ]

-- | Add common schema definitions
addCommonSchemas :: HM.InsOrdHashMap Text Schema -> HM.InsOrdHashMap Text Schema
addCommonSchemas schemas = schemas <> HM.fromList
    [ ("Error", errorSchema)
    , ("PaginatedResponse", paginatedResponseSchema)
    , ("ValidationError", validationErrorSchema)
    , ("RateLimit", rateLimitSchema)
    , ("AuditTrail", auditTrailSchema)
    ]
  where
    auditTrailSchema = mempty
        & type_ ?~ SwaggerObject
        & description ?~ "Audit trail information"
        & properties .~ HM.fromList
            [ ("id", mempty & type_ ?~ SwaggerString)
            , ("timestamp", mempty & type_ ?~ SwaggerString & format ?~ "date-time")
            , ("actor", mempty & type_ ?~ SwaggerString)
            , ("action", mempty & type_ ?~ SwaggerString)
            , ("resource", mempty & type_ ?~ SwaggerString)
            , ("details", mempty & type_ ?~ SwaggerObject)
            , ("ip_address", mempty & type_ ?~ SwaggerString)
            , ("user_agent", mempty & type_ ?~ SwaggerString)
            ]
        & required .~ ["id", "timestamp", "actor", "action"]

    errorSchema = mempty
        & type_ ?~ SwaggerObject
        & description ?~ "Error response"
        & properties .~ HM.fromList
            [ ("success", mempty & type_ ?~ SwaggerBoolean & example ?~ toJSON False)
            , ("error", mempty
                & type_ ?~ SwaggerObject
                & properties .~ HM.fromList
                    [ ("code", mempty & type_ ?~ SwaggerString)
                    , ("message", mempty & type_ ?~ SwaggerString)
                    ]
                )
            ]
        & required .~ ["success", "error"]

    validationErrorSchema = mempty
        & type_ ?~ SwaggerObject
        & description ?~ "Validation error details"
        & properties .~ HM.fromList
            [ ("field", mempty & type_ ?~ SwaggerString)
            , ("message", mempty & type_ ?~ SwaggerString)
            ]

    rateLimitSchema = mempty
        & type_ ?~ SwaggerObject
        & description ?~ "Rate limit information"
        & properties .~ HM.fromList
            [ ("limit", mempty & type_ ?~ SwaggerInteger)
            , ("remaining", mempty & type_ ?~ SwaggerInteger)
            , ("reset", mempty & type_ ?~ SwaggerInteger)
            ]

    paginatedResponseSchema = mempty
        & type_ ?~ SwaggerObject
        & description ?~ "Paginated response wrapper"
        & properties .~ HM.fromList
            [ ("success", mempty & type_ ?~ SwaggerBoolean & example ?~ toJSON True)
            , ("data", mempty & type_ ?~ SwaggerArray)
            , ("pagination", mempty
                & type_ ?~ SwaggerObject
                & properties .~ HM.fromList
                    [ ("total", mempty & type_ ?~ SwaggerInteger)
                    , ("per_page", mempty & type_ ?~ SwaggerInteger)
                    , ("current_page", mempty & type_ ?~ SwaggerInteger)
                    , ("last_page", mempty & type_ ?~ SwaggerInteger)
                    ]
                )
            ]
        & required .~ ["success", "data"]

    unauthorizedResponse = mempty
        & description .~ "Authentication failed"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "Error"))
        & headers .~ HM.fromList
            [ ("WWW-Authenticate", Header "WWW-Authenticate" (mempty & type_ ?~ SwaggerString))
            ]

    validationResponse = mempty
        & description .~ "Invalid request parameters"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "ValidationError"))

    notFoundResponse = mempty
        & description .~ "Resource not found"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "Error"))

    rateLimitResponse = mempty
        & description .~ "Rate limit exceeded"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "Error"))
        & headers .~ HM.fromList
            [ ("X-RateLimit-Limit", Header "X-RateLimit-Limit" (mempty & type_ ?~ SwaggerInteger))
            , ("X-RateLimit-Remaining", Header "X-RateLimit-Remaining" (mempty & type_ ?~ SwaggerInteger))
            , ("X-RateLimit-Reset", Header "X-RateLimit-Reset" (mempty & type_ ?~ SwaggerInteger))
            ]

    internalErrorResponse = mempty
        & description .~ "Internal server error"
        & content .~ HM.singleton "application/json" (mempty
            & schema ?~ Ref (Reference "Error"))

-- | Server for serving OpenAPI specification
swaggerServer :: Server SwaggerAPI
swaggerServer =
    return generateSwagger
    :<|> swaggerUIServer

-- | Serve Swagger UI
swaggerUIServer :: Server (SwaggerSchemaUI "swagger-ui" "openapi.json")
swaggerUIServer = swaggerSchemaUIServer generateSwagger
