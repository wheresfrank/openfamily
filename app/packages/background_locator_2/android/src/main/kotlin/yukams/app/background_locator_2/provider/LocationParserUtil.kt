package yukams.app.background_locator_2.provider

import android.location.Location
import android.os.Build
import com.google.android.gms.location.LocationResult
import yukams.app.background_locator_2.Keys
import java.util.HashMap

class LocationParserUtil {
    companion object {
        fun getLocationMapFromLocation(location: Location): HashMap<Any, Any> {
            var speedAccuracy = 0f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                speedAccuracy = location.speedAccuracyMetersPerSecond
            }
            var isMocked = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                isMocked = location.isFromMockProvider
            }

            val map = HashMap<Any, Any>()
            map[Keys.ARG_IS_MOCKED] = isMocked
            map[Keys.ARG_LATITUDE] = location.latitude
            map[Keys.ARG_LONGITUDE] = location.longitude
            map[Keys.ARG_ACCURACY] = location.accuracy
            map[Keys.ARG_ALTITUDE] = location.altitude
            map[Keys.ARG_SPEED] = location.speed
            map[Keys.ARG_SPEED_ACCURACY] = speedAccuracy
            map[Keys.ARG_HEADING] = location.bearing
            map[Keys.ARG_TIME] = location.time.toDouble()
            map[Keys.ARG_PROVIDER] = location.provider ?: ""
            return map
        }

        fun getLocationMapFromLocation(location: LocationResult?): HashMap<Any, Any>? {
            val firstLocation = location?.lastLocation ?: return null

            var speedAccuracy = 0f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                speedAccuracy = firstLocation.speedAccuracyMetersPerSecond
            }
            var isMocked = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                isMocked = firstLocation.isFromMockProvider
            }

            val map = HashMap<Any, Any>()
            map[Keys.ARG_IS_MOCKED] = isMocked
            map[Keys.ARG_LATITUDE] = firstLocation.latitude
            map[Keys.ARG_LONGITUDE] = firstLocation.longitude
            map[Keys.ARG_ACCURACY] = firstLocation.accuracy
            map[Keys.ARG_ALTITUDE] = firstLocation.altitude
            map[Keys.ARG_SPEED] = firstLocation.speed
            map[Keys.ARG_SPEED_ACCURACY] = speedAccuracy
            map[Keys.ARG_HEADING] = firstLocation.bearing
            map[Keys.ARG_TIME] = firstLocation.time.toDouble()
            return map
        }
    }
}