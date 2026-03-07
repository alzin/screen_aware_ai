package com.poc.screen_aware_ai

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import org.json.JSONArray
import org.json.JSONObject
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

    /**
     * Harvest the accessibility tree of the current foreground app.
     * Returns a compact JSON string containing only useful interactive/text elements.
     * Uses multiple windows for better coverage when the active window is sparse.
     * Limits: max ~200 elements, max depth ~20.
     */
    fun getUITree(): String {
        val elements = JSONArray()
        var elementCount = 0
        val maxElements = 200
        val maxDepth = 20

        fun traverse(node: AccessibilityNodeInfo, depth: Int) {
            if (elementCount >= maxElements || depth > maxDepth) return

            val bounds = Rect()
            node.getBoundsInScreen(bounds)

            val text = node.text?.toString()
            val contentDesc = node.contentDescription?.toString()
            val isClickable = node.isClickable
            val isEditable = node.isEditable
            val isCheckable = node.isCheckable
            val isScrollable = node.isScrollable
            val isVisible = node.isVisibleToUser
            val isFocusable = node.isFocusable
            val isLongClickable = node.isLongClickable

            // Include elements that are useful:
            // - have text or description (semantic content), OR
            // - are interactive (clickable, editable, checkable, scrollable, focusable)
            val isUseful = isVisible && (
                !text.isNullOrBlank() ||
                !contentDesc.isNullOrBlank() ||
                isClickable ||
                isEditable ||
                isCheckable ||
                isScrollable ||
                isLongClickable
            )

            if (isUseful && bounds.width() > 0 && bounds.height() > 0) {
                val className = node.className?.toString()?.substringAfterLast('.') ?: "View"

                val element = JSONObject().apply {
                    put("id", elementCount)
                    put("type", className)
                    if (!text.isNullOrBlank()) put("text", text)
                    if (!contentDesc.isNullOrBlank()) put("desc", contentDesc)
                    if (isClickable) put("clickable", true)
                    if (isEditable) put("editable", true)
                    if (isCheckable) {
                        put("checkable", true)
                        put("checked", node.isChecked)
                    }
                    if (isScrollable) put("scrollable", true)
                    if (isLongClickable) put("longClickable", true)
                    if (isFocusable) put("focusable", true)
                    put("bounds", JSONObject().apply {
                        put("cx", bounds.centerX())
                        put("cy", bounds.centerY())
                        put("w", bounds.width())
                        put("h", bounds.height())
                    })
                }
                elements.put(element)
                elementCount++
            }

            // Traverse children
            for (i in 0 until node.childCount) {
                if (elementCount >= maxElements) break
                val child = node.getChild(i) ?: continue
                traverse(child, depth + 1)
                child.recycle()
            }
        }

        // Try rootInActiveWindow first
        var rootNode = rootInActiveWindow
        val packageName: String

        if (rootNode != null) {
            packageName = rootNode.packageName?.toString() ?: "unknown"
            val rootChildCount = rootNode.childCount

            try {
                traverse(rootNode, 0)
            } catch (e: Exception) {
                Log.e(TAG, "getUITree: error traversing active window tree", e)
            } finally {
                rootNode.recycle()
            }

            // If the active window gave a sparse tree, try other windows too.
            // This can happen when apps use multiple windows (e.g., split views,
            // dialogs over content, or custom window layers).
            if (elementCount <= 3) {
                Log.d(TAG, "getUITree: sparse tree from active window ($elementCount elements, rootChildCount=$rootChildCount), trying all windows")
                try {
                    val allWindows = windows
                    for (window in allWindows) {
                        if (elementCount >= maxElements) break
                        // Focus on application windows — skip system UI, input method, etc.
                        if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                        val windowRoot = window.root ?: continue
                        // Skip if this is the same window we already traversed
                        val windowPkg = windowRoot.packageName?.toString()
                        if (windowPkg == packageName && rootChildCount > 0) {
                            windowRoot.recycle()
                            continue
                        }
                        try {
                            traverse(windowRoot, 0)
                        } catch (e: Exception) {
                            Log.w(TAG, "getUITree: error traversing window $windowPkg", e)
                        } finally {
                            windowRoot.recycle()
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "getUITree: windows fallback failed", e)
                }
            }
        } else {
            Log.w(TAG, "getUITree: rootInActiveWindow is null, trying windows list")
            packageName = tryGetPackageFromWindows(elements, ::traverse) ?: "unknown"
        }

        val result = JSONObject().apply {
            put("package", packageName)
            put("elements", elements)
        }

        Log.d(TAG, "getUITree: package=$packageName, elements=$elementCount")
        return result.toString()
    }

    /**
     * Fallback: when rootInActiveWindow is null, try to find the app window
     * from the windows list. Returns the package name if found.
     */
    private fun tryGetPackageFromWindows(
        elements: JSONArray,
        traverse: (AccessibilityNodeInfo, Int) -> Unit
    ): String? {
        try {
            val allWindows = windows
            for (window in allWindows) {
                if (window.type != AccessibilityWindowInfo.TYPE_APPLICATION) continue
                val root = window.root ?: continue
                val pkg = root.packageName?.toString()
                try {
                    traverse(root, 0)
                } catch (e: Exception) {
                    Log.w(TAG, "tryGetPackageFromWindows: error traversing $pkg", e)
                } finally {
                    root.recycle()
                }
                if (pkg != null) return pkg
            }
        } catch (e: Exception) {
            Log.w(TAG, "tryGetPackageFromWindows: failed", e)
        }
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
