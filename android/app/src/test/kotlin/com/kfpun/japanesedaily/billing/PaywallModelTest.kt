package com.kfpun.japanesedaily.billing

import com.kfpun.japanesedaily.audio.NotPremium
import com.kfpun.japanesedaily.billing.FakeBillingGateway.Companion.offer
import com.kfpun.japanesedaily.billing.FakeBillingGateway.Companion.purchase
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PaywallModelTest {
    private val gateway = FakeBillingGateway().apply {
        offers = listOf(
            offer(ProPlan.ONE_MONTH, 3.0),
            offer(ProPlan.SIX_MONTHS, 15.0),
            offer(ProPlan.TWELVE_MONTHS, 24.0),
            offer(ProPlan.LIFETIME, 60.0)
        )
    }

    @Test
    fun theBestValuePlanIsPreselected() = runTest(UnconfinedTestDispatcher()) {
        val model =
            PaywallModel(
                ProRepository(gateway, InMemoryEntitlementStore(), backgroundScope),
                backgroundScope,
                PaywallRequest("settings")
            )
        model.load()
        assertEquals(ProPlan.TWELVE_MONTHS, model.state.value.selected)
        assertEquals(4, model.state.value.offers.size)
        assertFalse(model.state.value.unavailable)
    }

    @Test
    fun noPlansMeansUnavailableWithARetry() = runTest(UnconfinedTestDispatcher()) {
        gateway.offers = emptyList()
        gateway.offersStatus = BillingStatus.UNAVAILABLE
        val model =
            PaywallModel(
                ProRepository(gateway, InMemoryEntitlementStore(), backgroundScope),
                backgroundScope,
                PaywallRequest("settings")
            )
        model.load()
        assertTrue(model.state.value.unavailable)
        gateway.offers = listOf(offer(ProPlan.ONE_MONTH, 3.0))
        gateway.offersStatus = BillingStatus.OK
        model.retry()
        assertFalse(model.state.value.unavailable)
        assertEquals(ProPlan.ONE_MONTH, model.state.value.selected)
    }

    @Test
    fun choosingAndPayingAreTwoSteps() = runTest(UnconfinedTestDispatcher()) {
        val pro = ProRepository(gateway, InMemoryEntitlementStore(), backgroundScope)
        val model = PaywallModel(pro, backgroundScope, PaywallRequest("locked_mode", lesson = 8))
        model.load()
        model.select(ProPlan.LIFETIME)
        assertTrue(gateway.launched.isEmpty()) // selecting never opens the sheet
        gateway.onLaunch =
            { BillingStatus.OK to PurchasesResult(BillingStatus.OK, listOf(purchase(ProProducts.lifetimeId))) }
        model.purchase(pro.launcher(android.app.Activity()))
        assertEquals(ProPlan.LIFETIME, gateway.launched.single().first.plan)
        assertTrue(pro.isPremium)
        assertNull(model.state.value.message)
        assertFalse(model.state.value.isPurchasing)
    }

    @Test
    fun cancelledPurchaseLeavesNoErrorAndAFailedOneSaysSo() = runTest(UnconfinedTestDispatcher()) {
        val pro = ProRepository(gateway, InMemoryEntitlementStore(), backgroundScope)
        val model = PaywallModel(pro, backgroundScope, PaywallRequest("settings"))
        model.load()
        model.purchase(pro.launcher(android.app.Activity())) // the fake's sheet is cancelled
        assertNull(model.state.value.message)
        gateway.onLaunch = { BillingStatus.ERROR to null }
        model.purchase(pro.launcher(android.app.Activity()))
        assertEquals(PaywallMessage.FAILED, model.state.value.message)
    }

    @Test
    fun restoreWithNothingToRestoreShowsTheMessage() = runTest(UnconfinedTestDispatcher()) {
        val pro = ProRepository(gateway, InMemoryEntitlementStore(), backgroundScope)
        val model = PaywallModel(pro, backgroundScope, PaywallRequest("settings"))
        model.restore()
        assertEquals(PaywallMessage.NOTHING_FOUND, model.state.value.message)
    }

    @Test
    fun theControllerOpensForFreeUsersAndNotForPro() {
        val free = PaywallController(NotPremium)
        free.open("locked_challenge", lesson = 6)
        assertEquals(PaywallRequest("locked_challenge", 6), free.request.value)
        free.close()
        assertNull(free.request.value)
        val pro = PaywallController(object : com.kfpun.japanesedaily.audio.PremiumStatus {
            override val isPremium = true
        })
        pro.open("settings")
        assertNull(pro.request.value)
    }
}
