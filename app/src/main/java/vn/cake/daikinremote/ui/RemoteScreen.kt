package vn.cake.daikinremote.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeFloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import vn.cake.daikinremote.protocol.Fan
import vn.cake.daikinremote.protocol.Mode

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RemoteScreen(ui: UiState, vm: RemoteViewModel) {
    val view = LocalView.current
    // Every button gives a short tick, like pressing a physical remote.
    fun tap(action: () -> Unit) = {
        view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        action()
    }
    val s = ui.state
    val p = ui.protocol
    var timerDialog by remember { mutableStateOf<Boolean?>(null) } // true = on timer, false = off
    val context = LocalContext.current
    // The phone-timer countdown lives in a notification; ask once when a timer is first set.
    val notifyPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Daikin Remote")
                        Text(p.displayName, style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                actions = { TextButton(onClick = vm::showPicker) { Text("Protocol") } },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Display(ui)

            ui.notice?.let {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(it, color = MaterialTheme.colorScheme.onTertiaryContainer)
                        Row {
                            TextButton(onClick = { openAppSettings(context) }) { Text("App settings") }
                            TextButton(onClick = vm::dismissNotice) { Text("OK") }
                        }
                    }
                }
            }

            ui.error?.let {
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("IR error: $it", Modifier.weight(1f), color = MaterialTheme.colorScheme.onErrorContainer)
                        TextButton(onClick = vm::dismissError) { Text("OK") }
                    }
                }
            }

            // Power + temperature
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                val powerColor by animateColorAsState(
                    if (s.power) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                    label = "power",
                )
                LargeFloatingActionButton(
                    onClick = tap(vm::power),
                    shape = CircleShape,
                    containerColor = powerColor,
                    contentColor = if (s.power) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                ) { Icon(PowerIcon, contentDescription = "Power", Modifier.size(40.dp)) }

                val range = p.tempRange(s.mode)
                val tempEnabled = s.mode != Mode.FAN
                BigButton("−", enabled = tempEnabled && s.tempC > range.first, Modifier.weight(1f), tap(vm::tempDown))
                BigButton("+", enabled = tempEnabled && s.tempC < range.last, Modifier.weight(1f), tap(vm::tempUp))
            }
            if (p.powerIsToggle) {
                Hint("This protocol toggles power. If the AC is out of sync with the app, press Power again.")
            }

            Section("Mode") {
                Choices(p.modes, s.mode, { it.label }) { tap { vm.mode(it) }() }
            }

            Section("Fan speed  ·  ${fanText(s.fan)}") {
                FanSelector(p.fans, s.fan) { tap { vm.fan(it) }() }
            }

            if (p.supportsSwingV || p.supportsSwingH) {
                Section("Swing") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (p.supportsSwingV) Toggle("↕ Up/down", s.swingV, Modifier.weight(1f), tap(vm::swingV))
                        if (p.supportsSwingH) Toggle("↔ Left/right", s.swingH, Modifier.weight(1f), tap(vm::swingH))
                    }
                }
            }

            Section("Timer") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TimerButton("ON", s.onTimerAt, ui.now, Modifier.weight(1f)) { timerDialog = true }
                    TimerButton("OFF", s.offTimerAt, ui.now, Modifier.weight(1f)) { timerDialog = false }
                }
                if (p.nativeTimer) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Run timer on the phone instead of the AC", Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium)
                        Switch(checked = ui.stored.phoneTimer, onCheckedChange = vm::setPhoneTimer)
                    }
                }
                if (ui.phoneTimer) {
                    Hint(
                        "This AC has no built-in IR timer, so the phone sends the command when it's due. " +
                            "Leave the phone pointed at the AC with the app allowed to run in the background.",
                    )
                    TextButton(onClick = { openAppSettings(context) }) { Text("App settings (Autostart / Battery)") }
                } else {
                    Hint("The timer is stored in the AC; the phone can be put away.")
                }
            }
            Spacer(Modifier.height(16.dp))
        }
    }

    timerDialog?.let { on ->
        TimerDialog(
            title = if (on) "Turn ON after…" else "Turn OFF after…",
            onPick = { minutes ->
                timerDialog = null
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                if (minutes != null && ui.phoneTimer && Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    notifyPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
                if (on) vm.onTimer(minutes) else vm.offTimer(minutes)
            },
            onDismiss = { timerDialog = null },
        )
    }
}

@Composable
private fun Display(ui: UiState) {
    val s = ui.state
    val alpha by animateFloatAsState(if (s.power) 1f else 0.45f, label = "dim")
    // Brief "sending" dot each time a frame goes out.
    var flash by remember { mutableStateOf(false) }
    LaunchedEffect(ui.sendCount) {
        if (ui.sendCount > 0) {
            flash = true
            delay(250)
            flash = false
        }
    }
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer),
    ) {
        Box(Modifier.fillMaxWidth().padding(20.dp)) {
            Column(Modifier.fillMaxWidth().alpha(alpha), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    if (s.power) "ON" else "OFF",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Text(
                    when (s.mode) {
                        Mode.FAN -> "Fan"
                        Mode.DRY -> "Dry"
                        else -> "${s.tempC}°"
                    },
                    fontSize = 88.sp,
                    fontWeight = FontWeight.Light,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                Text(
                    listOfNotNull(
                        s.mode.label,
                        "Fan: " + fanText(s.fan),
                        if (s.swingV) "↕" else null,
                        if (s.swingH) "↔" else null,
                    ).joinToString("  ·  "),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    textAlign = TextAlign.Center,
                )
                val timers = listOfNotNull(
                    s.onTimerAt?.let { "On at ${clock(it)} (${countdown(it, ui.now)})" },
                    s.offTimerAt?.let { "Off at ${clock(it)} (${countdown(it, ui.now)})" },
                )
                if (timers.isNotEmpty()) {
                    Text(timers.joinToString("  ·  "), style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onPrimaryContainer)
                }
            }
            if (flash) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .size(10.dp)
                        .background(MaterialTheme.colorScheme.tertiary, CircleShape),
                )
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(8.dp))
        content()
    }
}

@Composable
private fun <T> Choices(options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (o in options) {
            val modifier = Modifier.weight(1f)
            val pad = ButtonDefaults.TextButtonContentPadding
            if (o == selected) {
                Button(onClick = { onSelect(o) }, modifier, contentPadding = pad) { Text(label(o), maxLines = 1) }
            } else {
                OutlinedButton(onClick = { onSelect(o) }, modifier, contentPadding = pad) { Text(label(o), maxLines = 1) }
            }
        }
    }
}

@Composable
private fun Toggle(label: String, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    if (on) {
        Button(onClick = onClick, modifier) { Text(label) }
    } else {
        OutlinedButton(onClick = onClick, modifier) { Text(label) }
    }
}

@Composable
private fun BigButton(label: String, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    FilledTonalButton(onClick = onClick, enabled = enabled, modifier = modifier.height(72.dp)) {
        Text(label, fontSize = 36.sp)
    }
}

@Composable
private fun Hint(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun TimerDialog(title: String, onPick: (Int?) -> Unit, onDismiss: () -> Unit) {
    val options = listOf(15, 30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 720)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                options.chunked(4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { m ->
                            OutlinedButton(
                                onClick = { onPick(m) },
                                Modifier.weight(1f),
                                contentPadding = ButtonDefaults.TextButtonContentPadding,
                            ) { Text(if (m < 60) "${m}m" else if (m % 60 == 0) "${m / 60}h" else "${m / 60}.5h") }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onPick(null) }) { Text("Cancel timer") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}

private fun fanText(f: Fan) = when (f) {
    Fan.AUTO -> "Auto"
    Fan.QUIET -> "Quiet"
    else -> "Speed ${f.level} of 5"
}

/**
 * Auto / Quiet buttons plus five ascending bars like a signal meter: bars up to the chosen
 * speed are filled, and the number under each bar is the speed it selects.
 */
@Composable
private fun FanSelector(options: List<Fan>, selected: Fan, onSelect: (Fan) -> Unit) {
    val special = options.filter { it == Fan.AUTO || it == Fan.QUIET }
    val levels = options.filter { it != Fan.AUTO && it != Fan.QUIET }
    if (special.isNotEmpty()) Choices(special, selected, { it.label }, onSelect)
    if (levels.isEmpty()) return
    Spacer(Modifier.height(12.dp))
    val chosenLevel = if (selected in levels) selected.level else 0
    val on = MaterialTheme.colorScheme.primary
    val off = MaterialTheme.colorScheme.surfaceVariant
    Row(
        Modifier.fillMaxWidth().height(96.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        for (f in levels) {
            val filled = f.level <= chosenLevel
            val isChosen = f == selected
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onSelect(f) },
                verticalArrangement = Arrangement.Bottom,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height((14 + f.level * 12).dp)
                        .background(if (filled) on else off, RoundedCornerShape(6.dp)),
                )
                Text(
                    f.label,
                    fontWeight = if (isChosen) FontWeight.Bold else FontWeight.Normal,
                    color = if (isChosen) on else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun TimerButton(label: String, at: Long?, now: Long, modifier: Modifier, onClick: () -> Unit) {
    val content: @Composable () -> Unit = {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(if (at == null) "$label timer" else "$label at ${clock(at)}", maxLines = 1)
            Text(
                if (at == null) "not set" else countdown(at, now),
                style = MaterialTheme.typography.labelSmall,
            )
        }
    }
    if (at != null) {
        Button(onClick = onClick, modifier) { content() }
    } else {
        OutlinedButton(onClick = onClick, modifier) { content() }
    }
}

private fun openAppSettings(context: Context) {
    context.startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}
