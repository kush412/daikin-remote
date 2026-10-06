package vn.cake.daikinremote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import vn.cake.daikinremote.ui.ProtocolPickerScreen
import vn.cake.daikinremote.ui.RemoteScreen
import vn.cake.daikinremote.ui.RemoteTheme
import vn.cake.daikinremote.ui.RemoteViewModel
import vn.cake.daikinremote.ui.Screen

class MainActivity : ComponentActivity() {
    private val vm: RemoteViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RemoteTheme {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    val ui by vm.ui.collectAsStateWithLifecycle()
                    when {
                        !ui.hasEmitter -> NoIrBlaster()
                        !ui.loaded -> Unit
                        ui.screen == Screen.PICKER -> ProtocolPickerScreen(ui, vm)
                        else -> RemoteScreen(ui, vm)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        vm.refresh()
    }
}

@Composable
private fun NoIrBlaster() {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("No IR blaster found", style = MaterialTheme.typography.headlineSmall)
        Text(
            "This phone has no infrared emitter, so it can't talk to the AC. Phones with one include " +
                "many Xiaomi / Redmi / POCO models and some Huawei, Honor and Vivo models. A USB-C IR " +
                "dongle won't work with this app, because it uses Android's built-in IR service.",
            textAlign = TextAlign.Center,
        )
    }
}
