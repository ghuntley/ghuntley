{-|
Copyright (c) 2025 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
SPDX-License-Identifier: Proprietary
-}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Gerrit.Models.Invoice where

import Data.Aeson
import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH
import GHC.Generics

import Gerrit.Models.Types
import Gerrit.Models.Enterprise (Enterprise)
import Gerrit.Models.Organization (Organization)
import Gerrit.Models.Coupon (Coupon)

-- | Invoice status
data InvoiceStatus =
    Draft
  | Pending
  | Paid
  | Overdue
  | Cancelled
  | Refunded
  deriving (Show, Read, Eq, Generic)

instance ToJSON InvoiceStatus
instance FromJSON InvoiceStatus

derivePersistField "InvoiceStatus"

-- | Invoice line item
data LineItem = LineItem
  { description :: Text
  , quantity :: Int
  , unitPrice :: Double
  , amount :: Double
  , metadata :: Maybe Value
  } deriving (Show, Generic)

instance ToJSON LineItem
instance FromJSON LineItem

derivePersistField "LineItem"

-- | Invoice template
data InvoiceTemplate = InvoiceTemplate
  { templateName :: Text
  , headerContent :: Text
  , footerContent :: Text
  , customFields :: Value
  , style :: Value  -- ^ CSS styling
  } deriving (Show, Generic)

instance ToJSON InvoiceTemplate
instance FromJSON InvoiceTemplate

derivePersistField "InvoiceTemplate"

-- | Payment details
data PaymentDetails = PaymentDetails
  { method :: Text
  , transactionId :: Maybe Text
  , processorRef :: Maybe Text
  , paymentDate :: Maybe UTCTime
  , metadata :: Maybe Value
  } deriving (Show, Generic)

instance ToJSON PaymentDetails
instance FromJSON PaymentDetails

derivePersistField "PaymentDetails"

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Invoice
    invoiceId Text
    enterpriseId Text Maybe
    organizationId Text Maybe
    number Text
    status InvoiceStatus
    currency Text
    subtotal Double
    tax Double
    discount Double
    total Double
    items [LineItem]
    template InvoiceTemplate Maybe
    billingAddress Value
    paymentDetails PaymentDetails Maybe
    dueDate UTCTime
    paidDate UTCTime Maybe
    notes Text Maybe
    metadata Value Maybe
    createdBy Text
    created UTCTime
    updated UTCTime
    UniqueInvoiceId invoiceId
    UniqueInvoiceNumber number
    Foreign Enterprise enterpriseId References enterprises OnDeleteSetNull
    Foreign Organization organizationId References organizations OnDeleteSetNull
    deriving Show Eq Generic

InvoiceHistory
    historyId Text
    invoiceId Text
    changeType Text  -- ^ Created, Updated, Paid, etc.
    oldValue Value Maybe
    newValue Value
    reason Text Maybe
    changedBy Text
    timestamp UTCTime
    UniqueHistoryId historyId
    Foreign Invoice invoiceId References invoices OnDeleteCascade
    deriving Show Eq Generic

InvoiceCoupon
    invoiceId Text
    couponId Text
    appliedAmount Double
    metadata Value Maybe
    created UTCTime
    Primary invoiceId couponId
    Foreign Invoice invoiceId References invoices OnDeleteCascade
    Foreign Coupon couponId References coupons OnDeleteCascade
    deriving Show Eq Generic
|]

instance ToJSON (Entity Invoice)
instance ToJSON Invoice
instance FromJSON Invoice

instance ToJSON (Entity InvoiceHistory)
instance ToJSON InvoiceHistory
instance FromJSON InvoiceHistory

instance ToJSON (Entity InvoiceCoupon)
instance ToJSON InvoiceCoupon
instance FromJSON InvoiceCoupon
