package com.aalishms.opengym

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkoutTimerStateTest {
    private fun runningState() = WorkoutTimerState(
        sessionId = "session",
        planId = "plan",
        splitId = "split",
        planName = "Strength",
        weekNumber = 2,
        accumulatedSeconds = 30,
        runningSinceMillis = 1_000L,
        running = true,
        actionRevision = 1_000L,
        pendingStop = false,
    )

    @Test
    fun optionalBlockTextDoesNotChangeSessionIdentity() {
        val old = runningState()
        assertNull(old.blockName)
        assertEquals("Strength · Week 2", old.title())
        val labeled = old.copy(blockName = "Hypertrophy")
        assertEquals("Strength · Hypertrophy · Week 2", labeled.title())
        val resumed = labeled.paused(6_000L).resumed(10_000L)
        assertEquals("session", resumed.toMap()["sessionId"])
        assertEquals("Hypertrophy", resumed.toMap()["blockName"])
    }

    @Test
    fun elapsedCombinesAccumulatedTimeAndClampsBackwardClock() {
        val state = runningState()
        assertEquals(35, state.elapsedSeconds(6_000L))
        assertEquals(30, state.elapsedSeconds(500L))
    }

    @Test
    fun pauseFreezesElapsedTimeAndIsIdempotent() {
        val paused = runningState().paused(6_000L)
        assertEquals(35, paused.accumulatedSeconds)
        assertFalse(paused.running)
        assertNull(paused.runningSinceMillis)
        assertSame(paused, paused.paused(9_000L))
    }

    @Test
    fun stopMarksPausedStateAndResumeClearsRequest() {
        val stopped = runningState().paused(6_000L, stopRequested = true)
        assertTrue(stopped.pendingStop)
        val resumed = stopped.resumed(10_000L)
        assertTrue(resumed.running)
        assertFalse(resumed.pendingStop)
        assertEquals(10_000L, resumed.runningSinceMillis)
        assertEquals(35, resumed.accumulatedSeconds)
    }
}
