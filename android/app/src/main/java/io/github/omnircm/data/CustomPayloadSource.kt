package io.github.omnircm.data

data class CustomPayloadSource(
    val name: String,
    val repo: String,
    val assetMatch: String,
    val isZip: Boolean = false,
    val zipInnerPattern: String = "*.bin",
)
