package vn.cake.daikinremote.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp

private val Light = lightColorScheme(
    primary = Color(0xFF0A7CC1),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD3E9FA),
    onPrimaryContainer = Color(0xFF00304F),
    secondary = Color(0xFF4F6070),
    tertiary = Color(0xFFE5582B),
    background = Color(0xFFF6F9FC),
    surface = Color(0xFFF6F9FC),
    surfaceVariant = Color(0xFFE2EAF2),
)

private val Dark = darkColorScheme(
    primary = Color(0xFF8FCBFF),
    onPrimary = Color(0xFF003352),
    primaryContainer = Color(0xFF004B74),
    onPrimaryContainer = Color(0xFFD3E9FA),
    secondary = Color(0xFFB6C8DA),
    tertiary = Color(0xFFFFB59C),
    background = Color(0xFF0F1418),
    surface = Color(0xFF0F1418),
    surfaceVariant = Color(0xFF2A3540),
)

@Composable
fun RemoteTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) Dark else Light, content = content)
}

/** Material "power_settings_new" glyph (core icons don't include it). */
val PowerIcon: ImageVector = ImageVector.Builder("power", 24.dp, 24.dp, 24f, 24f).addPath(
    pathData = addPathNodes(
        "M13,3h-2v10h2L13,3zM17.83,5.17l-1.42,1.42C17.99,7.86 19,9.81 19,12c0,3.87 -3.13,7 -7,7" +
            "s-7,-3.13 -7,-7c0,-2.19 1.01,-4.14 2.58,-5.42L6.17,5.17C4.23,6.82 3,9.26 3,12c0,4.97 4.03,9 9,9" +
            "s9,-4.03 9,-9c0,-2.74 -1.23,-5.18 -3.17,-6.83z",
    ),
    fill = SolidColor(Color.Black),
).build()
