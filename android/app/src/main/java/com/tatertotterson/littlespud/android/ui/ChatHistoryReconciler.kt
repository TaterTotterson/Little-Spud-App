package com.tatertotterson.littlespud.android.ui

import com.tatertotterson.littlespud.android.model.HubActiveRun
import com.tatertotterson.littlespud.android.model.HubHistoryMessage
import com.tatertotterson.littlespud.android.model.LittleSpudAttachment
import com.tatertotterson.littlespud.android.model.LittleSpudMessage
import com.tatertotterson.littlespud.android.model.LittleSpudRole
import kotlin.math.abs

internal object ChatHistoryReconciler {
    fun merge(
        local: List<LittleSpudMessage>,
        incoming: List<HubHistoryMessage>,
        activeRuns: List<HubActiveRun>,
        isSending: Boolean,
    ): List<LittleSpudMessage> {
        val messages = dedupeLocal(local).toMutableList()
        incoming.sortedBy { it.createdAt }.forEach { row ->
            val incomingMessage = row.asLocalMessage()
            val idIndex = messages.indexOfFirst { it.id == row.id }
            if (idIndex >= 0) {
                messages[idIndex] = incomingMessage
                return@forEach
            }
            if (messages.any { isHubDuplicate(it, row) }) return@forEach
            if (row.role == LittleSpudRole.ASSISTANT && row.kind != "tool_notice") {
                val pendingIndex = messages.indexOfLast { message ->
                    message.role == LittleSpudRole.ASSISTANT &&
                        (message.kind in setOf("pending", "streaming") || message.content.isBlank()) &&
                        row.createdAt >= message.createdAt - 2_000
                }
                if (pendingIndex >= 0) {
                    if (!isSending && activeRuns.none(::isRunning)) {
                        val pending = messages[pendingIndex]
                        messages[pendingIndex] = incomingMessage.copy(
                            id = pending.id,
                            createdAt = pending.createdAt,
                        )
                    }
                    return@forEach
                }
            }
            messages += incomingMessage
        }

        val latestRun = activeRuns.filter(::isRunning).maxByOrNull { it.updatedAt }
        if (latestRun != null) {
            val text = latestRun.text.trim().ifBlank { "Tater is thinking" }
            val pendingIndex = messages.indexOfLast {
                it.role == LittleSpudRole.ASSISTANT && it.kind in setOf("pending", "streaming")
            }
            if (pendingIndex >= 0) {
                messages[pendingIndex] = messages[pendingIndex].copy(content = text, kind = "streaming")
            } else {
                val runId = "run-${latestRun.id}"
                if (messages.none { it.id == runId }) {
                    messages += LittleSpudMessage(
                        id = runId,
                        role = LittleSpudRole.ASSISTANT,
                        content = text,
                        createdAt = latestRun.startedAt,
                        kind = "streaming",
                    )
                }
            }
        }
        return dedupeLocal(messages).sortedBy { it.createdAt }.takeLast(200)
    }

    fun dedupeLocal(messages: List<LittleSpudMessage>): List<LittleSpudMessage> {
        val result = mutableListOf<LittleSpudMessage>()
        messages.sortedBy { it.createdAt }.forEach { candidate ->
            val sameIdIndex = result.indexOfFirst { it.id == candidate.id }
            if (sameIdIndex >= 0) {
                result[sameIdIndex] = richerMessage(result[sameIdIndex], candidate)
                return@forEach
            }
            val duplicateIndex = result.indexOfLast { existing ->
                abs(existing.createdAt - candidate.createdAt) <= NEARBY_DUPLICATE_WINDOW_MS &&
                    isLocalDuplicate(existing, candidate)
            }
            if (duplicateIndex >= 0) {
                result[duplicateIndex] = richerMessage(result[duplicateIndex], candidate)
            } else {
                result += candidate
            }
        }
        return result.sortedBy { it.createdAt }.takeLast(200)
    }

    private fun isHubDuplicate(existing: LittleSpudMessage, incoming: HubHistoryMessage): Boolean {
        if (existing.role != incoming.role) return false
        if ((existing.kind == "tool_notice") != (incoming.kind == "tool_notice")) return false
        if (existing.content.trim() != incoming.content.trim()) return false
        if (existing.attachments.isEmpty() && incoming.attachments.isEmpty()) return true
        val existingKeys = attachmentKeys(existing.attachments)
        val incomingKeys = attachmentKeys(incoming.attachments)
        if (existing.role == LittleSpudRole.USER && existingKeys.intersect(incomingKeys).isNotEmpty()) return true
        return abs(existing.createdAt - incoming.createdAt) <= ATTACHMENT_DUPLICATE_WINDOW_MS &&
            (existing.attachments.isNotEmpty() || incoming.attachments.isNotEmpty())
    }

    private fun isLocalDuplicate(first: LittleSpudMessage, second: LittleSpudMessage): Boolean {
        if (first.role != second.role) return false
        if ((first.kind == "tool_notice") != (second.kind == "tool_notice")) return false
        if (first.content.trim() != second.content.trim()) return false
        if (first.attachments.isEmpty() && second.attachments.isEmpty()) return true
        val firstKeys = attachmentKeys(first.attachments)
        val secondKeys = attachmentKeys(second.attachments)
        return firstKeys.intersect(secondKeys).isNotEmpty() ||
            first.attachments.isEmpty() || second.attachments.isEmpty()
    }

    private fun richerMessage(first: LittleSpudMessage, second: LittleSpudMessage): LittleSpudMessage {
        val firstIsPending = first.kind in setOf("pending", "streaming")
        val secondIsFinal = second.kind !in setOf("pending", "streaming") && second.content.isNotBlank()
        return first.copy(
            content = second.content.ifBlank { first.content },
            kind = if (firstIsPending && secondIsFinal) second.kind else first.kind,
            attachments = if (second.attachments.size > first.attachments.size) second.attachments else first.attachments,
            notificationTitle = first.notificationTitle ?: second.notificationTitle,
            notificationBody = first.notificationBody ?: second.notificationBody,
            notificationPriority = first.notificationPriority ?: second.notificationPriority,
        )
    }

    private fun attachmentKeys(attachments: List<LittleSpudAttachment>): Set<String> =
        attachments.mapNotNull { attachment ->
            val name = attachment.displayName.trim().lowercase()
            val type = attachment.type.trim().lowercase()
            if (name.isBlank() && type.isBlank() && attachment.size <= 0) null
            else "$name|$type|${attachment.size}"
        }.toSet()

    private fun HubHistoryMessage.asLocalMessage() = LittleSpudMessage(
        id = id,
        role = role,
        content = content,
        createdAt = createdAt,
        kind = kind,
        attachments = attachments,
    )

    private fun isRunning(run: HubActiveRun): Boolean =
        run.status.trim().lowercase().let { it.isBlank() || it == "queued" || it == "running" }

    private const val NEARBY_DUPLICATE_WINDOW_MS = 60_000L
    private const val ATTACHMENT_DUPLICATE_WINDOW_MS = 45_000L
}
