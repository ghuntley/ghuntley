-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gerrit.Api.Handlers.Billing
    ( handleListBillingPlans
    , handleCreateBillingPlan
    , handleGetBillingPlan
    , handleUpdateBillingPlan
    , handleCreateEnterpriseBilling
    , handleGetEnterpriseBilling
    , handleUpdateEnterpriseBilling
    , handleCreateBillingInvoice
    , handleGetBillingInvoice
    , handleUpdateBillingInvoice
    , handleListEnterpriseInvoices
    , handleCreateBillingTransaction
    , handleGetBillingTransaction
    , handleListInvoiceTransactions
    , handleListCoupons
    , handleCreateCoupon
    , handleGetCoupon
    , handleUpdateCoupon
    , handleValidateCoupon
    , handleApplyCoupon
    ) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (Value(..), object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Network.HTTP.Types.Status
import Web.Yesod

import Gerrit.Models.Billing
import Gerrit.Api.Types.Billing

-- | List billing plans
handleListBillingPlans :: Connection -> Handler Value
handleListBillingPlans conn = do
    plans <- listBillingPlans conn
    return $ toJSON plans

-- | Create billing plan
handleCreateBillingPlan :: Connection -> CreateBillingPlanRequest -> Handler Value
handleCreateBillingPlan conn CreateBillingPlanRequest{..} = do
    now <- liftIO getCurrentTime
    let plan = BillingPlan
            { bpId = generateId "plan"
            , bpName = cbpName
            , bpDisplayName = cbpDisplayName
            , bpDescription = cbpDescription
            , bpPricePerUser = cbpPricePerUser
            , bpFeatures = cbpFeatures
            , bpCreated = now
            , bpUpdated = now
            }
    plan' <- createBillingPlan conn plan
    return $ toJSON plan'

-- | Get billing plan by ID
handleGetBillingPlan :: Connection -> Text -> Handler Value
handleGetBillingPlan conn planId = do
    mPlan <- getBillingPlan conn planId
    case mPlan of
        Just plan -> return $ toJSON plan
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Billing plan not found" :: Text)]

-- | Update billing plan
handleUpdateBillingPlan :: Connection -> Text -> UpdateBillingPlanRequest -> Handler Value
handleUpdateBillingPlan conn planId UpdateBillingPlanRequest{..} = do
    mPlan <- getBillingPlan conn planId
    case mPlan of
        Just plan -> do
            now <- liftIO getCurrentTime
            let plan' = plan
                    { bpName = ubpName
                    , bpDisplayName = ubpDisplayName
                    , bpDescription = ubpDescription
                    , bpPricePerUser = ubpPricePerUser
                    , bpFeatures = ubpFeatures
                    , bpUpdated = now
                    }
            plan'' <- updateBillingPlan conn plan'
            return $ toJSON plan''
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Billing plan not found" :: Text)]

-- | Create enterprise billing
handleCreateEnterpriseBilling :: Connection -> Text -> CreateEnterpriseBillingRequest -> Handler Value
handleCreateEnterpriseBilling conn enterpriseId CreateEnterpriseBillingRequest{..} = do
    now <- liftIO getCurrentTime
    let billing = EnterpriseBilling
            { ebId = generateId "eb"
            , ebEnterpriseId = enterpriseId
            , ebPlanId = cebPlanId
            , ebStatus = Active
            , ebPaymentMethodId = cebPaymentMethodId
            , ebBillingEmail = cebBillingEmail
            , ebBillingAddress = cebBillingAddress
            , ebTaxId = cebTaxId
            , ebNextBillingDate = now  -- TODO: Calculate next billing date
            , ebLastBillingDate = Nothing
            , ebCreated = now
            , ebUpdated = now
            }
    billing' <- createEnterpriseBilling conn billing
    return $ toJSON billing'

-- | Get enterprise billing
handleGetEnterpriseBilling :: Connection -> Text -> Handler Value
handleGetEnterpriseBilling conn enterpriseId = do
    mBilling <- getEnterpriseBilling conn enterpriseId
    case mBilling of
        Just billing -> return $ toJSON billing
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Enterprise billing not found" :: Text)]

-- | Update enterprise billing
handleUpdateEnterpriseBilling :: Connection -> Text -> UpdateEnterpriseBillingRequest -> Handler Value
handleUpdateEnterpriseBilling conn enterpriseId UpdateEnterpriseBillingRequest{..} = do
    mBilling <- getEnterpriseBilling conn enterpriseId
    case mBilling of
        Just billing -> do
            now <- liftIO getCurrentTime
            let billing' = billing
                    { ebPlanId = uebPlanId
                    , ebStatus = uebStatus
                    , ebPaymentMethodId = uebPaymentMethodId
                    , ebBillingEmail = uebBillingEmail
                    , ebBillingAddress = uebBillingAddress
                    , ebTaxId = uebTaxId
                    , ebUpdated = now
                    }
            billing'' <- updateEnterpriseBilling conn billing'
            return $ toJSON billing''
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Enterprise billing not found" :: Text)]

-- | List coupons
handleListCoupons :: Connection -> Handler Value
handleListCoupons conn = do
    coupons <- listCoupons conn
    return $ toJSON coupons

-- | Create coupon
handleCreateCoupon :: Connection -> CreateCouponRequest -> Handler Value
handleCreateCoupon conn CreateCouponRequest{..} = do
    now <- liftIO getCurrentTime
    let coupon = Coupon
            { cpId = generateId "cpn"
            , cpCode = ccrCode
            , cpDescription = ccrDescription
            , cpDiscountType = ccrDiscountType
            , cpDiscountValue = ccrDiscountValue
            , cpValidFrom = ccrValidFrom
            , cpValidUntil = ccrValidUntil
            , cpMaxUses = ccrMaxUses
            , cpCurrentUses = 0
            , cpMinAmount = ccrMinAmount
            , cpMaxAmount = ccrMaxAmount
            , cpAllowedPlans = ccrAllowedPlans
            , cpCreated = now
            , cpUpdated = now
            }
    coupon' <- createCoupon conn coupon
    return $ toJSON coupon'

-- | Get coupon
handleGetCoupon :: Connection -> Text -> Handler Value
handleGetCoupon conn couponId = do
    mCoupon <- getCoupon conn couponId
    case mCoupon of
        Just coupon -> return $ toJSON coupon
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Coupon not found" :: Text)]

-- | Update coupon
handleUpdateCoupon :: Connection -> Text -> UpdateCouponRequest -> Handler Value
handleUpdateCoupon conn couponId UpdateCouponRequest{..} = do
    mCoupon <- getCoupon conn couponId
    case mCoupon of
        Just coupon -> do
            now <- liftIO getCurrentTime
            let coupon' = coupon
                    { cpCode = ucrCode
                    , cpDescription = ucrDescription
                    , cpDiscountType = ucrDiscountType
                    , cpDiscountValue = ucrDiscountValue
                    , cpValidFrom = ucrValidFrom
                    , cpValidUntil = ucrValidUntil
                    , cpMaxUses = ucrMaxUses
                    , cpMinAmount = ucrMinAmount
                    , cpMaxAmount = ucrMaxAmount
                    , cpAllowedPlans = ucrAllowedPlans
                    , cpUpdated = now
                    }
            coupon'' <- updateCoupon conn coupon'
            return $ toJSON coupon''
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Coupon not found" :: Text)]

-- | Validate coupon
handleValidateCoupon :: Connection -> ValidateCouponRequest -> Handler Value
handleValidateCoupon conn ValidateCouponRequest{..} = do
    mCoupon <- validateCoupon conn vcrCode vcrAmount vcrPlanId
    case mCoupon of
        Just coupon -> return $ toJSON $ CouponValidationResponse
            { cvrValid = True
            , cvrDiscountType = Just $ cpDiscountType coupon
            , cvrDiscountValue = Just $ cpDiscountValue coupon
            , cvrMessage = Nothing
            }
        Nothing -> return $ toJSON $ CouponValidationResponse
            { cvrValid = False
            , cvrDiscountType = Nothing
            , cvrDiscountValue = Nothing
            , cvrMessage = Just "Invalid or expired coupon"
            }

-- | Apply coupon to invoice
handleApplyCoupon :: Connection -> Text -> Text -> ApplyCouponRequest -> Handler Value
handleApplyCoupon conn enterpriseId invoiceId ApplyCouponRequest{..} = do
    mInvoice <- getBillingInvoice conn invoiceId
    case mInvoice of
        Just invoice -> do
            mCoupon <- validateCoupon conn acrCode (biAmount invoice) "any"  -- TODO: Get actual plan ID
            case mCoupon of
                Just coupon -> do
                    let discountAmount = calculateDiscount (cpDiscountType coupon) (cpDiscountValue coupon) (biAmount invoice)
                        finalAmount = biAmount invoice - discountAmount
                        invoice' = invoice
                            { biCouponId = Just $ cpId coupon
                            , biDiscountAmount = Just discountAmount
                            , biFinalAmount = finalAmount
                            }
                    invoice'' <- updateBillingInvoice conn invoice'
                    return $ toJSON invoice''
                Nothing -> sendResponseStatus status400 $
                    object ["error" .= ("Invalid or expired coupon" :: Text)]
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Invoice not found" :: Text)]

-- | Create billing invoice (updated to handle coupons)
handleCreateBillingInvoice :: Connection -> Text -> CreateBillingInvoiceRequest -> Handler Value
handleCreateBillingInvoice conn enterpriseId CreateBillingInvoiceRequest{..} = do
    now <- liftIO getCurrentTime
    (discountAmount, finalAmount, couponId) <- case cbiCouponCode of
        Just code -> do
            mCoupon <- validateCoupon conn code cbiAmount "any"  -- TODO: Get actual plan ID
            case mCoupon of
                Just coupon -> do
                    let discount = calculateDiscount (cpDiscountType coupon) (cpDiscountValue coupon) cbiAmount
                    return (Just discount, cbiAmount - discount, Just $ cpId coupon)
                Nothing -> sendResponseStatus status400 $
                    object ["error" .= ("Invalid or expired coupon" :: Text)]
        Nothing -> return (Nothing, cbiAmount, Nothing)

    let invoice = BillingInvoice
            { biId = generateId "inv"
            , biEnterpriseId = enterpriseId
            , biAmount = cbiAmount
            , biStatus = Draft
            , biDueDate = now  -- TODO: Parse due date from request
            , biPaidDate = Nothing
            , biLineItems = cbiLineItems
            , biCouponId = couponId
            , biDiscountAmount = discountAmount
            , biFinalAmount = finalAmount
            , biPaymentDetails = Nothing
            , biCreated = now
            , biUpdated = now
            }
    invoice' <- createBillingInvoice conn invoice
    return $ toJSON invoice'

-- | Get billing invoice
handleGetBillingInvoice :: Connection -> Text -> Handler Value
handleGetBillingInvoice conn invoiceId = do
    mInvoice <- getBillingInvoice conn invoiceId
    case mInvoice of
        Just invoice -> return $ toJSON invoice
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Invoice not found" :: Text)]

-- | Update billing invoice
handleUpdateBillingInvoice :: Connection -> Text -> Text -> UpdateBillingInvoiceRequest -> Handler Value
handleUpdateBillingInvoice conn enterpriseId invoiceId UpdateBillingInvoiceRequest{..} = do
    mInvoice <- getBillingInvoice conn invoiceId
    case mInvoice of
        Just invoice -> do
            now <- liftIO getCurrentTime
            let invoice' = invoice
                    { biStatus = ubiStatus
                    , biPaidDate = Nothing  -- TODO: Parse paid date from request
                    , biPaymentDetails = ubiPaymentDetails
                    , biUpdated = now
                    }
            invoice'' <- updateBillingInvoice conn invoice'
            return $ toJSON invoice''
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Invoice not found" :: Text)]

-- | List enterprise invoices
handleListEnterpriseInvoices :: Connection -> Text -> Handler Value
handleListEnterpriseInvoices conn enterpriseId = do
    invoices <- listEnterpriseInvoices conn enterpriseId
    return $ toJSON invoices

-- | Create billing transaction
handleCreateBillingTransaction :: Connection -> Text -> CreateBillingTransactionRequest -> Handler Value
handleCreateBillingTransaction conn invoiceId CreateBillingTransactionRequest{..} = do
    now <- liftIO getCurrentTime
    let transaction = BillingTransaction
            { btId = generateId "txn"
            , btInvoiceId = invoiceId
            , btAmount = cbtAmount
            , btStatus = TransactionPending
            , btPaymentMethod = cbtPaymentMethod
            , btPaymentDetails = cbtPaymentDetails
            , btCreated = now
            }
    transaction' <- createBillingTransaction conn transaction
    return $ toJSON transaction'

-- | Get billing transaction
handleGetBillingTransaction :: Connection -> Text -> Handler Value
handleGetBillingTransaction conn transactionId = do
    mTransaction <- getBillingTransaction conn transactionId
    case mTransaction of
        Just transaction -> return $ toJSON transaction
        Nothing -> sendResponseStatus status404 $
            object ["error" .= ("Transaction not found" :: Text)]

-- | List invoice transactions
handleListInvoiceTransactions :: Connection -> Text -> Handler Value
handleListInvoiceTransactions conn invoiceId = do
    transactions <- listInvoiceTransactions conn invoiceId
    return $ toJSON transactions

-- Helper functions

generateId :: Text -> Text
generateId prefix = undefined  -- TODO: Implement ID generation

-- | Helper function to calculate discount
calculateDiscount :: DiscountType -> Scientific -> Scientific -> Scientific
calculateDiscount Percentage value amount = (amount * value) / 100
calculateDiscount FixedAmount value _ = value
