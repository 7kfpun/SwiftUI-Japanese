package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.audio.PlaybackRates
import com.kfpun.japanesedaily.billing.FakeBillingGateway.Companion.offer
import com.kfpun.japanesedaily.billing.FakeBillingGateway.Companion.purchase
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The premium source against a fake Play client: re-read on start, cached, restore, purchase, cancel. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProRepositoryTest {
    private val gateway = FakeBillingGateway()
    private val store = InMemoryEntitlementStore()

    private fun TestScope.repository() = ProRepository(gateway, store, backgroundScope)

    private val sub = purchase(ProProducts.subscriptionId)
    private val lifetime = purchase(ProProducts.lifetimeId)

    @Test
    fun aFreshInstallIsFreeOnceTheSavedValueIsRead() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        assertEquals(Entitlement.FREE, pro.entitlement.value)
        assertFalse(pro.isPremium)
    }

    @Test
    fun startReReadsPlayAndTurnsProOn() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(sub)
        val pro = repository()
        assertEquals(Entitlement.PRO, pro.refresh())
        assertTrue(pro.isPremium)
        assertEquals(Entitlement.PRO, store.read())
        assertEquals(listOf(sub.purchaseToken), gateway.acknowledged) // acknowledged as soon as seen
    }

    @Test
    fun theLifetimeProductGrantsPro() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(lifetime.copy(isAcknowledged = true))
        val pro = repository()
        pro.refresh()
        assertTrue(pro.isPremium)
        assertTrue(gateway.acknowledged.isEmpty())
    }

    @Test
    fun aProductThatIsNotOursGrantsNothing() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(purchase("something.else"))
        val pro = repository()
        assertEquals(Entitlement.FREE, pro.refresh())
    }

    @Test
    fun theCachedValueHoldsFromTheFirstFrameAndWhenPlayIsUnreachable() = runTest(UnconfinedTestDispatcher()) {
        store.write(Entitlement.PRO)
        gateway.purchasesStatus = BillingStatus.UNAVAILABLE
        val pro = repository()
        assertTrue(pro.isPremium) // before any Play answer
        assertEquals(Entitlement.PRO, pro.refresh())
        assertTrue(pro.isPremium) // a paying user offline doesn't get ads
    }

    @Test
    fun anExpiredOrRefundedSubscriptionTurnsProOffOnTheNextStart() = runTest(UnconfinedTestDispatcher()) {
        store.write(Entitlement.PRO)
        gateway.owned = emptyList() // Play leaves out expired, refunded, revoked and on-hold ones
        val pro = repository()
        assertEquals(Entitlement.FREE, pro.refresh())
        assertEquals(Entitlement.FREE, store.read())
    }

    @Test
    fun onePremiumSourceDrivesTheAudioRates() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        assertEquals(1.0, PlaybackRates.effective(1.5, pro), 0.0)
        gateway.owned = listOf(sub)
        pro.refresh()
        assertEquals(1.5, PlaybackRates.effective(1.5, pro), 0.0)
    }

    @Test
    fun aFailedAcknowledgementIsRetriedOnTheNextRefresh() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(sub)
        gateway.acknowledgeStatus = BillingStatus.ERROR
        val pro = repository()
        pro.refresh()
        assertTrue(pro.isPremium)
        gateway.acknowledgeStatus = BillingStatus.OK
        pro.refresh()
        assertEquals(listOf(sub.purchaseToken), gateway.acknowledged)
    }

    @Test
    fun restoreFindsAPurchaseMadeOnAnotherDevice() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        gateway.owned = listOf(sub)
        assertEquals(RestoreOutcome.RESTORED, pro.restore())
        assertTrue(pro.isPremium)
        assertEquals(RestoreOutcome.ALREADY_PREMIUM, pro.restore())
    }

    @Test
    fun restoreWithNothingToRestoreSaysSo() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        assertEquals(RestoreOutcome.NOTHING_FOUND, pro.restore())
        assertFalse(pro.isPremium)
    }

    @Test
    fun restoreWhilePlayIsDownFailsAndKeepsWhatWeKnow() = runTest(UnconfinedTestDispatcher()) {
        store.write(Entitlement.PRO)
        gateway.purchasesStatus = BillingStatus.UNAVAILABLE
        val pro = repository()
        assertEquals(RestoreOutcome.FAILED, pro.restore())
        assertTrue(pro.isPremium)
    }

    @Test
    fun aPurchaseSucceedsAndTurnsProOn() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        gateway.onLaunch = { BillingStatus.OK to PurchasesResult(BillingStatus.OK, listOf(sub)) }
        val plan = offer(ProPlan.SIX_MONTHS, 15.0)
        assertEquals(PurchaseOutcome.PURCHASED, pro.purchase(plan, pro.launcher(activity())))
        assertTrue(pro.isPremium)
        assertNull(gateway.launched.single().second) // nothing owned yet, so no plan switch
    }

    @Test
    fun cancellingTheSheetChangesNothing() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        val outcome = pro.purchase(offer(ProPlan.ONE_MONTH, 3.0), pro.launcher(activity()))
        assertEquals(PurchaseOutcome.NOT_COMPLETED, outcome)
        assertFalse(pro.isPremium)
    }

    @Test
    fun aSlowPaymentIsPendingUntilPlayConfirmsIt() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        val pending = purchase(ProProducts.lifetimeId, state = OwnedPurchase.State.PENDING)
        gateway.onLaunch = { BillingStatus.OK to PurchasesResult(BillingStatus.OK, listOf(pending)) }
        assertEquals(PurchaseOutcome.PENDING, pro.purchase(offer(ProPlan.LIFETIME, 60.0), pro.launcher(activity())))
        assertEquals(Entitlement.PENDING, pro.entitlement.value)
        assertFalse(pro.isPremium) // pending is not Pro, and still gets ads
    }

    @Test
    fun buyingAnotherPlanSwitchesTheSubscriptionInsteadOfAddingOne() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(sub.copy(isAcknowledged = true))
        val pro = repository()
        pro.refresh()
        gateway.onLaunch =
            {
                BillingStatus.OK to PurchasesResult(
                    BillingStatus.OK,
                    listOf(purchase(ProProducts.subscriptionId, "new"))
                )
            }
        pro.purchase(offer(ProPlan.TWELVE_MONTHS, 24.0), pro.launcher(activity()))
        assertEquals(sub.purchaseToken, gateway.launched.single().second)
    }

    @Test
    fun lifetimeIsNeverBoughtAsAPlanSwitch() = runTest(UnconfinedTestDispatcher()) {
        gateway.owned = listOf(sub.copy(isAcknowledged = true))
        val pro = repository()
        pro.refresh()
        gateway.onLaunch = { BillingStatus.OK to PurchasesResult(BillingStatus.OK, listOf(lifetime)) }
        pro.purchase(offer(ProPlan.LIFETIME, 60.0), pro.launcher(activity()))
        assertNull(gateway.launched.single().second)
    }

    @Test
    fun alreadyOwnedFallsBackToARestore() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        gateway.owned = listOf(sub)
        gateway.onLaunch = { BillingStatus.ITEM_ALREADY_OWNED to null }
        assertEquals(PurchaseOutcome.PURCHASED, pro.purchase(offer(ProPlan.ONE_MONTH, 3.0), pro.launcher(activity())))
        assertTrue(pro.isPremium)
    }

    @Test
    fun anUnavailablePlayIsAFailedPurchase() = runTest(UnconfinedTestDispatcher()) {
        val pro = repository()
        gateway.onLaunch = { BillingStatus.UNAVAILABLE to null }
        assertEquals(PurchaseOutcome.FAILED, pro.purchase(offer(ProPlan.ONE_MONTH, 3.0), pro.launcher(activity())))
    }

    @Test
    fun lifetimeOutranksASubscriptionHeldBesideIt() {
        val tier = ProRepository.tierOf(listOf(sub, lifetime))
        assertEquals("lifetime", tier)
        assertEquals("subscription", ProRepository.tierOf(listOf(sub)))
        assertEquals("none", ProRepository.tierOf(emptyList()))
    }

    /** The fake ignores the activity; a bare android.jar stub is enough. */
    private fun activity() = android.app.Activity()
}
