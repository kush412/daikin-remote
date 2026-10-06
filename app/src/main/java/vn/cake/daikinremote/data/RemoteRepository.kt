package vn.cake.daikinremote.data

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Process-wide single source of truth for the remote state. The UI and the timer receiver both
 * go through it, so a timer firing while the app is open shows up immediately and is never
 * overwritten by a stale UI copy. Updates are serialized, so rapid taps are applied in order.
 */
class RemoteRepository private constructor(context: Context) {
    private val store = StateStore(context)
    private val mutex = Mutex()
    private val _stored = MutableStateFlow<Stored?>(null)

    /** null until first loaded from disk. */
    val stored: StateFlow<Stored?> = _stored.asStateFlow()

    suspend fun current(): Stored = mutex.withLock { loadLocked() }

    /** Atomically transforms and persists the state; returns the new value. */
    suspend fun update(change: suspend (Stored) -> Stored): Stored = mutex.withLock {
        val next = change(loadLocked())
        _stored.value = next
        store.save(next)
        next
    }

    private suspend fun loadLocked(): Stored = _stored.value ?: store.load().also { _stored.value = it }

    companion object {
        @Volatile private var instance: RemoteRepository? = null

        fun get(context: Context): RemoteRepository =
            instance ?: synchronized(this) {
                instance ?: RemoteRepository(context.applicationContext).also { instance = it }
            }
    }
}
