package yukams.app.background_locator_2

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Receives movement-state transitions from [ActivityTransitionsManager],
 * records the current classification for the Dart background isolate (which
 * attaches it to location reports as `motion_state`), and asks the running
 * locator service to apply the matching location profile.
 */
class ActivityTransitionsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = ActivityTransitionResult.extractResult(intent) ?: return

        var isMoving = false
        var label = ""
        for (event in result.transitionEvents) {
            val entering = event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER
            when (event.activityType) {
                DetectedActivity.STILL -> {
                    isMoving = false
                    label = "stationary"
                }
                DetectedActivity.IN_VEHICLE -> {
                    isMoving = true
                    label = "driving"
                }
                DetectedActivity.ON_BICYCLE -> {
                    isMoving = true
                    label = "cycling"
                }
                DetectedActivity.WALKING -> {
                    isMoving = true
                    label = "walking"
                }
                DetectedActivity.RUNNING -> {
                    isMoving = true
                    label = "running"
                }
                else -> if (entering) {
                    isMoving = true
                    label = ""
                }
            }
        }

        PreferencesManager.setMotionState(context, label)

        // Only wake the service when the state actually flipped; repeated
        // enter/exit events within one class (e.g. brief walking pauses) would
        // otherwise churn the location client.
        IsolateHolderService.applyMotionProfile(context, isMoving)
    }
}
