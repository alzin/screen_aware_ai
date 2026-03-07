package com.poc.screen_aware_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class ScreenActionService : AccessibilityService() {

    companion object {
        var instance: ScreenActionService? = null
        private const val TAG = "ScreenActionService"
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to process events for this PoC
    }

    override fun onInterrupt() {
        // Required override
    }

    /**
     * Dispatch a gesture and wait for completion (up to 2 seconds).
     * Returns true if completed, false if cancelled or timed out.
     */
    private fun dispatchGestureSync(gesture: GestureDescription): Boolean {
        val latch = CountDownLatch(1)
        var success = false

        val dispatched = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                super.onCompleted(gestureDescription)
                success = true
                latch.countDown()
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                super.onCancelled(gestureDescription)
                Log.w(TAG, "Gesture was cancelled")
                success = false
                latch.countDown()
            }
        }, null)

        if (!dispatched) {
            Log.e(TAG, "dispatchGesture returned false — gesture not dispatched")
            return false
        }

        // Wait up to 2 seconds for the gesture to complete
        latch.await(2, TimeUnit.SECONDS)
        return success
    }

    fun performTap(x: Float, y: Float): Boolean {
        Log.d(TAG, "performTap($x, $y)")
        val path = Path()
        path.moveTo(x, y)

        val gestureBuilder = GestureDescription.Builder()
        gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, 100))

        return dispatchGestureSync(gestureBuilder.build())
    }

    fun performType(text: String) {
        val rootNode = rootInActiveWindow ?: return
        val focusedNode = findFocusedEditText(rootNode)

        if (focusedNode != null) {
            val arguments = Bundle()
            arguments.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text
            )
            focusedNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }
        rootNode.recycle()
    }

    private fun findFocusedEditText(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isFocused && node.isEditable) {
            return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findFocusedEditText(child)
            if (result != null) return result
            child.recycle()
        }
        return null
    }

    fun performSwipe(startX: Float, startY: Float, endX: Float, endY: Float, durationMs: Long = 300): Boolean {
        Log.d(TAG, "performSwipe($startX, $startY -> $endX, $endY)")
        val path = Path()
        path.moveTo(startX, startY)
        path.lineTo(endX, endY)

        val gestureBuilder = GestureDescription.Builder()
        gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))

        return dispatchGestureSync(gestureBuilder.build())
    }

    fun pressBack() {
        performGlobalAction(GLOBAL_ACTION_BACK)
    }

    fun pressHome() {
        performGlobalAction(GLOBAL_ACTION_HOME)
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
