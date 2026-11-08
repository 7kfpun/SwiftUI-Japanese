package com.kfpun.japanesedaily.billing

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

/** The last entitlement Play confirmed, so Pro holds offline and from the first frame. */
interface EntitlementStore {
    suspend fun read(): Entitlement?

    suspend fun write(entitlement: Entitlement)
}

// files/datastore/pro.preferences_pb: left out of every backup (data_extraction_rules.xml excludes
// the whole file domain, allowBackup is false), since Play is the source of truth on a new phone.
private val Context.proDataStore by preferencesDataStore(name = "pro")

class DataStoreEntitlementStore(context: Context) : EntitlementStore {
    private val dataStore = context.applicationContext.proDataStore
    private val key = stringPreferencesKey("entitlement")

    override suspend fun read(): Entitlement? = dataStore.data.first()[key]?.let { name ->
        Entitlement.entries.firstOrNull { it.name == name }
    }

    override suspend fun write(entitlement: Entitlement) {
        dataStore.edit { it[key] = entitlement.name }
    }
}

/** Keeps the entitlement in memory only: tests, and a container built without a Context. */
class InMemoryEntitlementStore(private var value: Entitlement? = null) : EntitlementStore {
    override suspend fun read(): Entitlement? = value

    override suspend fun write(entitlement: Entitlement) {
        value = entitlement
    }
}
