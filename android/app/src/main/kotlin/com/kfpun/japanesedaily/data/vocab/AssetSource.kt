package com.kfpun.japanesedaily.data.vocab

import android.content.res.AssetManager
import java.io.File
import java.io.InputStream

/**
 * Where the bundled course files come from. The app reads the APK's assets (the `minna` flavour
 * packages `nihongo/Resources` as them); JVM tests read the same folder from disk.
 */
interface AssetSource {
    fun open(path: String): InputStream

    /** The file names directly inside [dir], or empty when there is no such directory. */
    fun list(dir: String): Set<String>
}

class AndroidAssetSource(private val assets: AssetManager) : AssetSource {
    override fun open(path: String): InputStream = assets.open(path)

    override fun list(dir: String): Set<String> = assets.list(dir)?.toSet().orEmpty()
}

class FileAssetSource(private val root: File) : AssetSource {
    override fun open(path: String): InputStream = File(root, path).inputStream()

    override fun list(dir: String): Set<String> = File(root, dir).list()?.toSet().orEmpty()
}
