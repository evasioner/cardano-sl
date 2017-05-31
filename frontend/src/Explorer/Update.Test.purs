module Explorer.Update.Test where

import Prelude
import Control.Monad.Aff (Aff)
import Control.Monad.State (StateT)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Generic (gShow)
import Data.Identity (Identity)
import Data.Lens ((^.), set)
import Data.Newtype (unwrap)
import Data.Time.NominalDiffTime (mkTime)
import Data.Tuple (Tuple(..))
import Explorer.Api.Types (SocketSubscription(..), SocketSubscriptionData(..))
import Explorer.I18n.Lang (Language(..))
import Explorer.Lenses.State (connected, dbViewBlockPagination, dbViewLoadingBlockPagination, dbViewMaxBlockPagination, dbViewNextBlockPagination, lang, latestBlocks, latestTransactions, loading, socket, subscriptions)
import Explorer.State (initialState, mkSocketSubscriptionItem)
import Explorer.Test.MockFactory (mkCBlockEntry, mkEmptyCTxEntry, setEpochSlotOfBlock, setHashOfBlock, setIdOfTx, setTimeOfTx)
import Explorer.Types.Actions (Action(..))
import Explorer.Types.State (PageNumber(..), PageSize(..))
import Explorer.Update (update)
import Explorer.Util.Factory (mkCHash, mkCTxId)
import Explorer.View.Dashboard.Lenses (dashboardViewState)
import Network.RemoteData (RemoteData(..), isLoading, isNotAsked, withDefault)
import Pos.Explorer.Socket.Methods (Subscription(..))
import Test.Spec (Group, describe, it)
import Test.Spec.Assertions (shouldEqual)

testUpdate :: forall r. StateT (Array (Group (Aff r Unit))) Identity Unit
testUpdate =
    describe "Explorer.Update" do

        describe "uses action SetLanguage" do
            it "to update language"
                let effModel =  update (SetLanguage German) initialState
                    state = _.state effModel
                    result = state ^. lang
                in result `shouldEqual` German

        describe "uses action SocketBlocksUpdated" do
            -- Mock blocks with epoch, slots and hashes
            let totalPages = 70
                blockA = setEpochSlotOfBlock 0 1 $ setHashOfBlock (mkCHash "A") mkCBlockEntry
                blockB = setEpochSlotOfBlock 0 2 $ setHashOfBlock (mkCHash "B") mkCBlockEntry
                blockC = setEpochSlotOfBlock 1 0 $ setHashOfBlock (mkCHash "C") mkCBlockEntry
                blockD = setEpochSlotOfBlock 1 1 $ setHashOfBlock (mkCHash "D") mkCBlockEntry
                currentBlocks =
                    [ blockA
                    , blockB
                    ]
                -- set `latestBlocks` to mock some previous blocks
                initialState' =
                    set latestBlocks (Success currentBlocks) initialState
                newBlocks =
                    [ blockB
                    , blockC
                    , blockD
                    ]
                effModel = update (SocketBlocksUpdated (Right (Tuple totalPages newBlocks))) initialState'
                state = _.state effModel
            it "to update latestBlocks w/o duplicates"
                let result = withDefault [] $ state ^. latestBlocks
                    expected =
                        [ blockB
                        , blockC
                        , blockD
                        ]
                in (gShow result) `shouldEqual` (gShow expected)
            it "to count total pages"
                let result = unwrap <<< withDefault (PageNumber 0) $ state ^. (dashboardViewState <<< dbViewMaxBlockPagination )
                in result `shouldEqual` totalPages

        describe "handles RequestPaginatedBlocks action" do
            let effModel = update DashboardRequestBlocksTotalPages initialState
                state = _.state effModel
            it "to set loading state of dbViewMaxBlockPaginations" do
                (isLoading $ state ^. (dashboardViewState <<< dbViewMaxBlockPagination)) `shouldEqual` true

        describe "handles RequestPaginatedBlocks action" do
            let effModel = update (RequestPaginatedBlocks (PageNumber 1) (PageSize 1)) initialState
                state = _.state effModel
            it "to set dbViewLoadingBlockPagination to true" do
                (state ^. (dashboardViewState <<< dbViewLoadingBlockPagination)) `shouldEqual` true
            it "to not update state of latestBlocks" do
                (isNotAsked $ state ^. latestBlocks) `shouldEqual` true

        describe "handles DashboardReceiveBlocksTotalPages action" do
            let totalPages = 70
                effModel = update (DashboardReceiveBlocksTotalPages $ Right totalPages) initialState
                state = _.state effModel
            it "to update dbViewMaxBlockPagination to number of total pages"
                let result = unwrap <<< withDefault (PageNumber 0) $ state ^. (dashboardViewState <<< dbViewMaxBlockPagination )
                in result `shouldEqual` totalPages
            it "to update dbViewBlockPagination to number of total pages"
                let result = unwrap $ state ^. (dashboardViewState <<< dbViewBlockPagination )
                in result `shouldEqual` totalPages

        describe "uses action ReceivePaginatedBlocks" do
            -- Mock blocks with epoch, slots and hashes
            let blockA = setEpochSlotOfBlock 2 1 $ setHashOfBlock (mkCHash "A") mkCBlockEntry
                blockB = setEpochSlotOfBlock 2 0 $ setHashOfBlock (mkCHash "B") mkCBlockEntry
                blockC = setEpochSlotOfBlock 1 9 $ setHashOfBlock (mkCHash "C") mkCBlockEntry
                blockD = setEpochSlotOfBlock 1 8 $ setHashOfBlock (mkCHash "D") mkCBlockEntry
                blockE = setEpochSlotOfBlock 1 7 $ setHashOfBlock (mkCHash "E") mkCBlockEntry
                currentBlocks =
                    [ blockA
                    , blockB
                    , blockC
                    ]
                pageNumber = PageNumber 2
                -- set `latestBlocks` to simulate that we have already blocks before
                initialState' =
                    set latestBlocks (Success currentBlocks) $
                    set (dashboardViewState <<< dbViewNextBlockPagination) pageNumber
                    initialState
                paginatedBlocks =
                    [ blockC
                    , blockD
                    , blockE
                    ]
                totalPages = 10
                effModel = update (ReceivePaginatedBlocks (Right (Tuple totalPages paginatedBlocks))) initialState'
                state = _.state effModel
            it "to add blocks to latestBlocks"
                let result = withDefault [] $ state ^. latestBlocks
                in (gShow result) `shouldEqual` (gShow paginatedBlocks)
            it "to update number of total pages"
                let result = unwrap <<< withDefault (PageNumber 0) $ state ^. (dashboardViewState <<< dbViewMaxBlockPagination )
                in result `shouldEqual` totalPages
            it "to set loading to false" do
                (state ^. loading) `shouldEqual` false
            it "to update dbViewBlockPagination by using dbViewNextBlockPagination"
                let result = (state ^. (dashboardViewState <<< dbViewBlockPagination))
                in (gShow result) `shouldEqual` (gShow pageNumber)
            it "to set dbViewLoadingBlockPagination to false" do
                (state ^. (dashboardViewState <<< dbViewLoadingBlockPagination))
                    `shouldEqual` false

        describe "uses action SocketTxsUpdated" do
            -- Mock txs
            let txA = setTimeOfTx (mkTime 0.1) $ setIdOfTx (mkCTxId "A") mkEmptyCTxEntry
                txB = setTimeOfTx (mkTime 0.2) $ setIdOfTx (mkCTxId "B") mkEmptyCTxEntry
                txC = setTimeOfTx (mkTime 1.0) $ setIdOfTx (mkCTxId "C") mkEmptyCTxEntry
                txD = setTimeOfTx (mkTime 2.1) $ setIdOfTx (mkCTxId "D") mkEmptyCTxEntry
                currentTxs =
                    [ txA
                    , txB
                    ]
                -- set `latestTransactions` to simulate that we have already txs before
                initialState' =
                    set latestTransactions (Success currentTxs) initialState
                newTxs =
                    [ txA
                    , txC
                    , txD
                    ]
                effModel = update (SocketTxsUpdated (Right newTxs)) initialState'
                state = _.state effModel
            it "to update latestTransactions w/o duplicates and sorted by time"
                let result = withDefault [] $ state ^. latestTransactions
                    expected =
                        [ txD
                        , txC
                        , txB
                        , txA
                        ]
                in (gShow result) `shouldEqual` (gShow expected)

        describe "handles ReceiveLastTxs action" do
            -- Mock txs
            let txA = setTimeOfTx (mkTime 0.1) $ setIdOfTx (mkCTxId "A") mkEmptyCTxEntry
                txB = setTimeOfTx (mkTime 0.2) $ setIdOfTx (mkCTxId "B") mkEmptyCTxEntry
                txC = setTimeOfTx (mkTime 1.0) $ setIdOfTx (mkCTxId "C") mkEmptyCTxEntry
                newTxs =
                    [ txA
                    , txC
                    , txB
                    ]
                effModel = update (SocketTxsUpdated (Right newTxs)) initialState
                state = _.state effModel
            it "to update latestTransactions sorted by time"
                let result = withDefault [] $ state ^. latestTransactions
                    expected =
                        [ txC
                        , txB
                        , txA
                        ]
                in (gShow result) `shouldEqual` (gShow expected)

        describe "handles DashboardPaginateBlocks action" do
            let newPage = PageNumber 4
                effModel = update (DashboardPaginateBlocks newPage) initialState
                state = _.state effModel
            it "to set dbViewNextBlockPagination"
                let result = state ^. (dashboardViewState <<< dbViewNextBlockPagination)
                in (gShow result) `shouldEqual` (gShow newPage)
        describe "uses action SocketConnected" do
            it "to update connection to connected"
                let effModel = update (SocketConnected true) initialState
                    state = _.state effModel
                    result = state ^. socket <<< connected
                in result `shouldEqual` true
            it "to update connection to disconnected"
                let effModel = update (SocketConnected false) initialState
                    state = _.state effModel
                    result = state ^. socket <<< connected
                in result `shouldEqual` false

        describe "uses action SocketAddSubscription" do
            it "to add a first subscription"
                let subItem = mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                    effModel = update (SocketAddSubscription subItem) initialState
                    state = _.state effModel
                    result = state ^. socket <<< subscriptions
                in (gShow result) `shouldEqual` (gShow [subItem])
            it "to add another subscription"
                let initialState' = set (socket <<< subscriptions)
                                        [ mkSocketSubscriptionItem (SocketSubscription SubTx) SocketNoData
                                        ]
                                        initialState
                    subItem = mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                    effModel = update (SocketAddSubscription subItem) initialState'
                    state = _.state effModel
                    result = state ^. socket <<< subscriptions
                    expected =  [ mkSocketSubscriptionItem (SocketSubscription SubTx) SocketNoData
                                , mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                                ]
                in (gShow result) `shouldEqual` (gShow expected)

        describe "uses action SocketRemoveSubscription" do
            it "to not remove anything, if we do have an empty list of subscriptions"
                let subItem = mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                    effModel = update (SocketRemoveSubscription subItem) initialState
                    state = _.state effModel
                    result = length $ state ^. socket <<< subscriptions
                in result `shouldEqual` 0
            it "to remove a subscription"
                let subItem = mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                    initialState' = set (socket <<< subscriptions)
                                        [ mkSocketSubscriptionItem (SocketSubscription SubTx) SocketNoData
                                        , mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                                        ]
                                        initialState
                    effModel = update (SocketRemoveSubscription subItem) initialState'
                    state = _.state effModel
                    result = state ^. socket <<< subscriptions
                in  (gShow result) `shouldEqual`
                    (gShow [mkSocketSubscriptionItem (SocketSubscription SubTx) SocketNoData])

        describe "uses action SocketClearSubscriptions" do

            it "to remove nothing if no subscription available"
                let effModel = update SocketClearSubscriptions initialState
                    state = _.state effModel
                    result = state ^. socket <<< subscriptions
                in length result `shouldEqual` 0

            it "to remove all subscription"
                let initialState' = set (socket <<< subscriptions)
                                        [ mkSocketSubscriptionItem (SocketSubscription SubTx) SocketNoData
                                        , mkSocketSubscriptionItem (SocketSubscription SubBlock) SocketNoData
                                        ]
                                        initialState
                    effModel = update SocketClearSubscriptions initialState'
                    state = _.state effModel
                    result = state ^. socket <<< subscriptions
                in length result `shouldEqual` 0
