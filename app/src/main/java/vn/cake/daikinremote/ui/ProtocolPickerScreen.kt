package vn.cake.daikinremote.ui

import android.view.HapticFeedbackConstants
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import vn.cake.daikinremote.protocol.Protocols

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProtocolPickerScreen(ui: UiState, vm: RemoteViewModel) {
    val view = LocalView.current
    val canGoBack = ui.stored.protocolId != null
    BackHandler(enabled = canGoBack) { vm.closePicker() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Find your AC's protocol") },
                navigationIcon = {
                    if (canGoBack) {
                        IconButton(onClick = vm::closePicker) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    "Point the top of the phone at the AC from 1–3 m away. Tap “Test ON” on each protocol, " +
                        "starting at the top, until the AC beeps and starts (Cool 24°C). Then tap “Use this”.\n\n" +
                        "If you know your remote's model number (printed on its back), look for it below.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                ui.error?.let {
                    Text("IR error: $it", color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.padding(top = 8.dp))
                }
            }
            items(Protocols.all, key = { it.id }) { p ->
                val current = p.id == ui.stored.protocolId
                Card(
                    colors = CardDefaults.cardColors(
                        containerColor = if (current) MaterialTheme.colorScheme.primaryContainer
                        else MaterialTheme.colorScheme.surfaceVariant,
                    ),
                ) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(p.displayName + if (current) "  (in use)" else "", style = MaterialTheme.typography.titleMedium)
                        Text(p.remotes, style = MaterialTheme.typography.bodySmall)
                        if (p.powerIsToggle) {
                            Text("Power is a toggle: Test ON and Test OFF both flip it.",
                                style = MaterialTheme.typography.bodySmall)
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilledTonalButton(onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                                vm.test(p, power = true)
                            }, Modifier.weight(1f), contentPadding = ButtonDefaults.TextButtonContentPadding) { Text("Test ON", maxLines = 1) }
                            OutlinedButton(onClick = {
                                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                                vm.test(p, power = false)
                            }, Modifier.weight(1f), contentPadding = ButtonDefaults.TextButtonContentPadding) { Text("Test OFF", maxLines = 1) }
                            Button(onClick = { vm.choose(p) }, Modifier.weight(1f), contentPadding = ButtonDefaults.TextButtonContentPadding) { Text("Use this", maxLines = 1) }
                        }
                    }
                }
            }
        }
    }
}
