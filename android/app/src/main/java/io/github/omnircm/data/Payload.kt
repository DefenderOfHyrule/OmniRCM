package io.github.omnircm.data

import java.io.File

data class Payload(
    val name: String,
    val file: File,
    val isRemote: Boolean = false,
    val isCustom: Boolean = false,
    val version: String? = null,
)
