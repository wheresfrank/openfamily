package yukams.app.background_locator_2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires on the repeating liveness alarm and forwards the tick into the Dart
 * background isolate.
 *
 * If the background engine is gone the tracking service was stopped or killed;
 * a heartbeat without active tracking would be misleading (the family map
 * shows position freshness, not bare process liveness), so the tick is dropped
 * and the next service start re-arms the alarm.
 */
class HeartbeatReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Keys.ACTION_HEARTBEAT) return
        IsolateHolderService.dispatchHeartbeat(context)
    }
}
