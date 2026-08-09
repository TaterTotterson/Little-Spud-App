package com.tatertotterson.littlespud.android.ui

import com.tatertotterson.littlespud.android.model.HubHistoryMessage
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ChatHistoryReconcilerTest {
    @Test
    fun hubIdsDoNotDuplicateLocallySentConversation() {
        val local = listOf(
            message("local-user", LittleSpudRole.USER, "Hello", 1_000),
            message("local-assistant", LittleSpudRole.ASSISTANT, "Hi there", 2_000),
        )
        val incoming = listOf(
            history("hub-user", LittleSpudRole.USER, "Hello", 1_050),
            history("hub-assistant", LittleSpudRole.ASSISTANT, "Hi there", 2_050),
        )

        val merged = ChatHistoryReconciler.merge(local, incoming, emptyList(), isSending = false)

        assertEquals(2, merged.size)
        assertEquals(listOf("Hello", "Hi there"), merged.map { it.content })
    }

    @Test
    fun previouslySavedNearbyDuplicatesAreRepaired() {
        val duplicated = listOf(
            message("local-user", LittleSpudRole.USER, "First", 1_000),
            message("hub-user", LittleSpudRole.USER, "First", 1_100),
            message("local-assistant", LittleSpudRole.ASSISTANT, "Reply", 2_000),
            message("hub-assistant", LittleSpudRole.ASSISTANT, "Reply", 2_100),
        )

        val repaired = ChatHistoryReconciler.dedupeLocal(duplicated)

        assertEquals(2, repaired.size)
    }

    @Test
    fun identicalMessagesFarApartRemainSeparate() {
        val messages = listOf(
            message("first", LittleSpudRole.USER, "Okay", 1_000),
            message("later", LittleSpudRole.USER, "Okay", 62_000),
        )

        assertEquals(2, ChatHistoryReconciler.dedupeLocal(messages).size)
    }

    @Test
    fun completedHubReplyReplacesPendingBubble() {
        val local = listOf(
            message("pending", LittleSpudRole.ASSISTANT, "", 2_000, kind = "streaming"),
        )
        val incoming = listOf(
            history("hub-reply", LittleSpudRole.ASSISTANT, "Finished", 2_100),
        )

        val merged = ChatHistoryReconciler.merge(local, incoming, emptyList(), isSending = false)

        assertEquals(1, merged.size)
        assertEquals("pending", merged.single().id)
        assertEquals("Finished", merged.single().content)
        assertFalse(merged.single().kind == "streaming")
    }

    private fun message(
        id: String,
        role: LittleSpudRole,
        content: String,
        createdAt: Long,
        kind: String? = null,
    ) = LittleSpudMessage(id = id, role = role, content = content, createdAt = createdAt, kind = kind)

    private fun history(
        id: String,
        role: LittleSpudRole,
        content: String,
        createdAt: Long,
    ) = HubHistoryMessage(id = id, role = role, content = content, createdAt = createdAt, kind = null)
}
