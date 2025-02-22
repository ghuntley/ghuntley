-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Gerrit.Api.Types.Billing where

import Data.Aeson
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics

import Gerrit.Models.Billing (BillingStatus(..), InvoiceStatus(..), TransactionStatus(..), DiscountType(..))

-- | Request to create a billing plan
data CreateBillingPlanRequest = CreateBillingPlanRequest
    { cbpName :: Text
    , cbpDisplayName :: Text
    , cbpDescription :: Maybe Text
    , cbpPricePerUser :: Scientific
    , cbpFeatures :: Value
    } deriving (Show, Generic)

instance FromJSON CreateBillingPlanRequest
instance ToJSON CreateBillingPlanRequest

-- | Request to update a billing plan
data UpdateBillingPlanRequest = UpdateBillingPlanRequest
    { ubpName :: Text
    , ubpDisplayName :: Text
    , ubpDescription :: Maybe Text
    , ubpPricePerUser :: Scientific
    , ubpFeatures :: Value
    } deriving (Show, Generic)

instance FromJSON UpdateBillingPlanRequest
instance ToJSON UpdateBillingPlanRequest

-- | Request to create enterprise billing
data CreateEnterpriseBillingRequest = CreateEnterpriseBillingRequest
    { cebPlanId :: Text
    , cebPaymentMethodId :: Maybe Text
    , cebBillingEmail :: Text
    , cebBillingAddress :: Value
    , cebTaxId :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON CreateEnterpriseBillingRequest
instance ToJSON CreateEnterpriseBillingRequest

-- | Request to update enterprise billing
data UpdateEnterpriseBillingRequest = UpdateEnterpriseBillingRequest
    { uebPlanId :: Text
    , uebStatus :: BillingStatus
    , uebPaymentMethodId :: Maybe Text
    , uebBillingEmail :: Text
    , uebBillingAddress :: Value
    , uebTaxId :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON UpdateEnterpriseBillingRequest
instance ToJSON UpdateEnterpriseBillingRequest

-- | Request to create a billing invoice
data CreateBillingInvoiceRequest = CreateBillingInvoiceRequest
    { cbiAmount :: Scientific
    , cbiDueDate :: Text
    , cbiLineItems :: Value
    , cbiCouponCode :: Maybe Text
    } deriving (Show, Generic)

instance FromJSON CreateBillingInvoiceRequest
instance ToJSON CreateBillingInvoiceRequest

-- | Request to update a billing invoice
data UpdateBillingInvoiceRequest = UpdateBillingInvoiceRequest
    { ubiStatus :: InvoiceStatus
    , ubiPaidDate :: Maybe Text
    , ubiPaymentDetails :: Maybe Value
    } deriving (Show, Generic)

instance FromJSON UpdateBillingInvoiceRequest
instance ToJSON UpdateBillingInvoiceRequest

-- | Request to create a billing transaction
data CreateBillingTransactionRequest = CreateBillingTransactionRequest
    { cbtAmount :: Scientific
    , cbtPaymentMethod :: Text
    , cbtPaymentDetails :: Value
    } deriving (Show, Generic)

instance FromJSON CreateBillingTransactionRequest
instance ToJSON CreateBillingTransactionRequest

-- | Generic success response
data SuccessResponse = SuccessResponse
    { success :: Bool
    } deriving (Show, Generic)

instance ToJSON SuccessResponse

-- | Generic error response
data ErrorResponse = ErrorResponse
    { error :: Text
    } deriving (Show, Generic)

instance ToJSON ErrorResponse

-- | Request to create a coupon
data CreateCouponRequest = CreateCouponRequest
    { ccrCode :: Text
    , ccrDescription :: Maybe Text
    , ccrDiscountType :: DiscountType
    , ccrDiscountValue :: Scientific
    , ccrValidFrom :: UTCTime
    , ccrValidUntil :: Maybe UTCTime
    , ccrMaxUses :: Maybe Int
    , ccrMinAmount :: Maybe Scientific
    , ccrMaxAmount :: Maybe Scientific
    , ccrAllowedPlans :: Maybe [Text]
    } deriving (Show, Generic)

instance FromJSON CreateCouponRequest
instance ToJSON CreateCouponRequest

-- | Request to update a coupon
data UpdateCouponRequest = UpdateCouponRequest
    { ucrCode :: Text
    , ucrDescription :: Maybe Text
    , ucrDiscountType :: DiscountType
    , ucrDiscountValue :: Scientific
    , ucrValidFrom :: UTCTime
    , ucrValidUntil :: Maybe UTCTime
    , ucrMaxUses :: Maybe Int
    , ucrMinAmount :: Maybe Scientific
    , ucrMaxAmount :: Maybe Scientific
    , ucrAllowedPlans :: Maybe [Text]
    } deriving (Show, Generic)

instance FromJSON UpdateCouponRequest
instance ToJSON UpdateCouponRequest

-- | Request to validate a coupon
data ValidateCouponRequest = ValidateCouponRequest
    { vcrCode :: Text
    , vcrAmount :: Scientific
    , vcrPlanId :: Text
    } deriving (Show, Generic)

instance FromJSON ValidateCouponRequest
instance ToJSON ValidateCouponRequest

-- | Request to apply a coupon to an invoice
data ApplyCouponRequest = ApplyCouponRequest
    { acrCode :: Text
    } deriving (Show, Generic)

instance FromJSON ApplyCouponRequest
instance ToJSON ApplyCouponRequest

-- | Coupon validation response
data CouponValidationResponse = CouponValidationResponse
    { cvrValid :: Bool
    , cvrDiscountType :: Maybe DiscountType
    , cvrDiscountValue :: Maybe Scientific
    , cvrMessage :: Maybe Text
    } deriving (Show, Generic)

instance ToJSON CouponValidationResponse
