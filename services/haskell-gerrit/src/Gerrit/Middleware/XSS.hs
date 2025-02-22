{-|
Module      : Gerrit.Middleware.XSS
Description : XSS protection middleware and HTML sanitization
Copyright   : (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>
License     : Proprietary
Maintainer  : Geoffrey Huntley <ghuntley@ghuntley.com>
Stability   : experimental
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Gerrit.Middleware.XSS
    ( XSSConfig(..)
    , defaultXSSConfig
    , xssMiddleware
    , sanitizeHTML
    , sanitizeForContext
    , Context(..)
    , AllowedTag(..)
    , AllowedAttribute(..)
    ) where

import Control.Monad (when)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as BC
import Data.Char (isAlphaNum, ord)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Types (ResponseHeaders, Header)
import Network.Wai
import Text.HTML.SanitizeXSS (sanitize)
import qualified Text.HTML.SanitizeXSS as XSSF
import Numeric (showHex)
import qualified CMark
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Time.Clock (getCurrentTime)
import Data.Aeson (ToJSON(..), object, (.=))
import qualified Data.Aeson as JSON

-- | XSS protection configuration
data XSSConfig = XSSConfig
    { allowedTags :: [AllowedTag]        -- ^ List of allowed HTML tags
    , allowedAttributes :: [AllowedAttribute]  -- ^ List of allowed attributes
    , cspPolicy :: ByteString            -- ^ Content Security Policy
    , enableXSSProtection :: Bool        -- ^ Enable X-XSS-Protection header
    , enableFrameOptions :: Bool         -- ^ Enable X-Frame-Options header
    , enableContentTypeOptions :: Bool   -- ^ Enable X-Content-Type-Options header
    , auditFailures :: Bool              -- ^ Enable audit logging of failures
    , rateLimitPerMinute :: Int          -- ^ Rate limit for sanitization requests
    }

-- | Allowed HTML tag with attributes
data AllowedTag = AllowedTag
    { tagName :: Text
    , tagAttributes :: [Text]
    }

-- | Allowed attribute with validation
data AllowedAttribute = AllowedAttribute
    { attrName :: Text
    , attrValidation :: Text -> Bool
    }

-- | Content context for sanitization
data Context
    = HTMLContext
    | JavaScriptContext
    | CSSContext
    | URLContext
    | MarkdownContext

-- | Default XSS configuration with enhanced security
defaultXSSConfig :: XSSConfig
defaultXSSConfig = XSSConfig
    { allowedTags =
        [ AllowedTag "p" []
        , AllowedTag "br" []
        , AllowedTag "b" []
        , AllowedTag "i" []
        , AllowedTag "em" []
        , AllowedTag "strong" []
        , AllowedTag "a" ["href", "rel"]
        , AllowedTag "img" ["src", "alt", "title"]
        , AllowedTag "code" []
        , AllowedTag "pre" []
        , AllowedTag "ul" []
        , AllowedTag "ol" []
        , AllowedTag "li" []
        , AllowedTag "blockquote" []
        ]
    , allowedAttributes =
        [ AllowedAttribute "href" isValidURL
        , AllowedAttribute "src" isValidURL
        , AllowedAttribute "alt" (const True)
        , AllowedAttribute "title" (const True)
        , AllowedAttribute "rel" isValidRel
        ]
    , cspPolicy = T.encodeUtf8 $ T.intercalate "; "
        [ "default-src 'self'"
        , "script-src 'self' 'unsafe-inline' 'unsafe-eval'"  -- Required for some UI frameworks
        , "style-src 'self' 'unsafe-inline'"                 -- Required for inline styles
        , "img-src 'self' https: data:"                      -- Allow HTTPS images and data URIs
        , "font-src 'self' https:"                           -- Allow HTTPS fonts
        , "connect-src 'self'"                               -- API endpoints
        , "frame-ancestors 'none'"                           -- Prevent clickjacking
        , "form-action 'self'"                               -- Restrict form submissions
        , "base-uri 'self'"                                  -- Restrict base URI
        , "require-trusted-types-for 'script'"               -- Enable Trusted Types
        ]
    , enableXSSProtection = True
    , enableFrameOptions = True
    , enableContentTypeOptions = True
    , auditFailures = True
    , rateLimitPerMinute = 1000
    }

-- | Audit log entry for sanitization
data SanitizationAudit = SanitizationAudit
    { saTimestamp :: UTCTime
    , saContext :: Context
    , saContentType :: Text
    , saOriginalContent :: Text
    , saFailureReason :: Maybe Text
    } deriving (Show)

instance ToJSON SanitizationAudit where
    toJSON SanitizationAudit{..} = object
        [ "timestamp" .= saTimestamp
        , "context" .= show saContext
        , "contentType" .= saContentType
        , "originalContent" .= saOriginalContent
        , "failureReason" .= saFailureReason
        ]

-- | Log sanitization failure with audit
logSanitizationFailure :: MonadIO m => XSSConfig -> Context -> Text -> Text -> Text -> m ()
logSanitizationFailure config context contentType content reason = when (auditFailures config) $ liftIO $ do
    now <- getCurrentTime
    let audit = SanitizationAudit
            { saTimestamp = now
            , saContext = context
            , saContentType = contentType
            , saOriginalContent = content
            , saFailureReason = Just reason
            }
    -- Log to audit system (implement based on your logging infrastructure)
    putStrLn $ "XSS Sanitization Failure: " ++ show (JSON.encode audit)

-- | Check if rel attribute value is valid
isValidRel :: Text -> Bool
isValidRel rel = rel `elem` ["nofollow", "noopener", "noreferrer"]

-- | Render Markdown to HTML safely
renderMarkdown :: Text -> Text
renderMarkdown content = T.pack $ CMark.commonmarkToHtml
    [ CMark.optSafe                -- Enable safe mode
    , CMark.optNormalize          -- Normalize the output
    , CMark.optValidate           -- Validate the output
    , CMark.optSmart              -- Enable smart punctuation
    ] . T.unpack $ content

-- | Sanitize content based on context
sanitizeForContext :: XSSConfig -> Context -> Text -> Text
sanitizeForContext config context = case context of
    HTMLContext -> sanitizeHTML config
    JavaScriptContext -> escapeJavaScript
    CSSContext -> escapeCSS
    URLContext -> escapeURL
    MarkdownContext -> sanitizeMarkdown config

-- | Sanitize Markdown content
sanitizeMarkdown :: XSSConfig -> Text -> Text
sanitizeMarkdown config content = do
    let htmlContent = renderMarkdown content
    sanitizeHTML config htmlContent

-- | Helper function to validate and sanitize URLs in Markdown
validateMarkdownURL :: Text -> Bool
validateMarkdownURL url = isValidURL url && not (containsJavaScript url)
  where
    containsJavaScript url = T.toLower (T.take 11 url) == "javascript:"

-- | XSS protection middleware
xssMiddleware :: XSSConfig -> Middleware
xssMiddleware config app req respond = app req $ \res -> do
    let headers = securityHeaders config
    respond $ mapResponseHeaders (headers ++) res

-- | Add security headers
securityHeaders :: XSSConfig -> ResponseHeaders
securityHeaders XSSConfig{..} = filter (not . null . snd)
    [ ("Content-Security-Policy", cspPolicy)
    , ("X-XSS-Protection", if enableXSSProtection then "1; mode=block" else "")
    , ("X-Frame-Options", if enableFrameOptions then "SAMEORIGIN" else "")
    , ("X-Content-Type-Options", if enableContentTypeOptions then "nosniff" else "")
    ]

-- | Sanitize HTML content
sanitizeHTML :: XSSConfig -> Text -> Text
sanitizeHTML config = sanitize . applyTagWhitelist (allowedTags config)

-- | Apply tag whitelist to HTML
applyTagWhitelist :: [AllowedTag] -> Text -> Text
applyTagWhitelist tags = XSSF.sanitizeBalance . XSSF.sanitizeAllowTags allowedTagNames
  where
    allowedTagNames = map tagName tags

-- | Escape JavaScript content
escapeJavaScript :: Text -> Text
escapeJavaScript = T.concatMap escapeJSChar
  where
    escapeJSChar c = case c of
        '"'  -> "\\\""
        '\\' -> "\\\\"
        '\n' -> "\\n"
        '\r' -> "\\r"
        '\t' -> "\\t"
        x    -> T.singleton x

-- | Escape CSS content
escapeCSS :: Text -> Text
escapeCSS = T.concatMap escapeCSSChar
  where
    escapeCSSChar c = case c of
        '"'  -> "\\\""
        '\\' -> "\\\\"
        '\n' -> "\\A "
        '\r' -> "\\D "
        x    -> T.singleton x

-- | Escape URL content
escapeURL :: Text -> Text
escapeURL = T.concatMap escapeURLChar
  where
    escapeURLChar c
        | isURLSafe c = T.singleton c
        | otherwise = T.pack $ '%' : showHex (ord c) ""

-- | Check if URL is valid
isValidURL :: Text -> Bool
isValidURL url = case T.uncons url of
    Just ('h', rest) -> T.isPrefixOf "ttp://" rest || T.isPrefixOf "ttps://" rest
    Just ('/', _) -> True
    _ -> False

-- | Check if character is URL safe
isURLSafe :: Char -> Bool
isURLSafe c = isAlphaNum c || c `elem` ("-_.~" :: String)
