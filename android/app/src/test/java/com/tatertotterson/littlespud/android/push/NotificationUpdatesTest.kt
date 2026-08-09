package com.tatertotterson.littlespud.android.push

import org.junit.Assert.assertEquals
import org.junit.Test

class NotificationUpdatesTest {
    @Test
    fun publishAdvancesRevision() {
        val updates = NotificationUpdates()

        updates.publish()
        updates.publish()

        assertEquals(2L, updates.revision.value)
    }
}
