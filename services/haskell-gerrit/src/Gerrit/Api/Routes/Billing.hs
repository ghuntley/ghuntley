-- Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
-- SPDX-License-Identifier: Proprietary

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}

module Gerrit.Api.Routes.Billing where

import Data.Text (Text)
import Web.Yesod

import Gerrit.Api.Handlers.Billing
import Gerrit.Api.Types.Billing

-- | Billing routes
mkYesodSubData "BillingApi" [parseRoutes|
/billing/plans                                BillingPlansR         GET POST
/billing/plans/#Text                         BillingPlanR          GET PUT
/billing/coupons                             CouponsR              GET POST
/billing/coupons/#Text                       CouponR               GET PUT
/billing/coupons/validate                    ValidateCouponR       POST
/enterprises/#Text/billing                    EnterpriseBillingR    GET POST PUT
/enterprises/#Text/billing/invoices           InvoicesR             GET POST
/enterprises/#Text/billing/invoices/#Text     InvoiceR              GET PUT
/enterprises/#Text/billing/invoices/#Text/coupon InvoiceCouponR    POST
/enterprises/#Text/billing/invoices/#Text/transactions TransactionsR GET POST
/enterprises/#Text/billing/transactions/#Text TransactionR          GET
|]

instance YesodSubDispatch BillingApi (HandlerFor App) where
    yesodSubDispatch = $(mkYesodSubDispatch resourcesBillingApi)

-- | Billing plan handlers
getBillingPlansR :: Handler Value
getBillingPlansR = handleListBillingPlans

postBillingPlansR :: Handler Value
postBillingPlansR = do
    req <- requireCheckJsonBody
    handleCreateBillingPlan req

getBillingPlanR :: Text -> Handler Value
getBillingPlanR = handleGetBillingPlan

putBillingPlanR :: Text -> Handler Value
putBillingPlanR planId = do
    req <- requireCheckJsonBody
    handleUpdateBillingPlan planId req

-- | Enterprise billing handlers
getEnterpriseBillingR :: Text -> Handler Value
getEnterpriseBillingR = handleGetEnterpriseBilling

postEnterpriseBillingR :: Text -> Handler Value
postEnterpriseBillingR enterpriseId = do
    req <- requireCheckJsonBody
    handleCreateEnterpriseBilling enterpriseId req

putEnterpriseBillingR :: Text -> Handler Value
putEnterpriseBillingR enterpriseId = do
    req <- requireCheckJsonBody
    handleUpdateEnterpriseBilling enterpriseId req

-- | Invoice handlers
getInvoicesR :: Text -> Handler Value
getInvoicesR = handleListEnterpriseInvoices

postInvoicesR :: Text -> Handler Value
postInvoicesR enterpriseId = do
    req <- requireCheckJsonBody
    handleCreateBillingInvoice enterpriseId req

getInvoiceR :: Text -> Text -> Handler Value
getInvoiceR _ = handleGetBillingInvoice

putInvoiceR :: Text -> Text -> Handler Value
putInvoiceR enterpriseId invoiceId = do
    req <- requireCheckJsonBody
    handleUpdateBillingInvoice enterpriseId invoiceId req

-- | Transaction handlers
getTransactionsR :: Text -> Text -> Handler Value
getTransactionsR _ = handleListInvoiceTransactions

postTransactionsR :: Text -> Text -> Handler Value
postTransactionsR _ invoiceId = do
    req <- requireCheckJsonBody
    handleCreateBillingTransaction invoiceId req

getTransactionR :: Text -> Text -> Handler Value
getTransactionR _ = handleGetBillingTransaction

-- | Coupon handlers
getCouponsR :: Handler Value
getCouponsR = handleListCoupons

postCouponsR :: Handler Value
postCouponsR = do
    req <- requireCheckJsonBody
    handleCreateCoupon req

getCouponR :: Text -> Handler Value
getCouponR = handleGetCoupon

putCouponR :: Text -> Handler Value
putCouponR couponId = do
    req <- requireCheckJsonBody
    handleUpdateCoupon couponId req

postValidateCouponR :: Handler Value
postValidateCouponR = do
    req <- requireCheckJsonBody
    handleValidateCoupon req

postInvoiceCouponR :: Text -> Text -> Handler Value
postInvoiceCouponR enterpriseId invoiceId = do
    req <- requireCheckJsonBody
    handleApplyCoupon enterpriseId invoiceId req
