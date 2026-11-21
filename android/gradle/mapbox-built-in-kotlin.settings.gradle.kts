// Mapbox 2.x mantém um bloco de KGP para AGP < 9. O verificador do Flutter
// identifica esse bloco mesmo quando ele não é executado. Este app usa AGP 9
// com Kotlin integrado, então gera uma cópia do script sem esse bloco legado.
check(providers.gradleProperty("android.builtInKotlin").orNull == "true") {
    "A adaptação Android do Mapbox exige android.builtInKotlin=true."
}

val mapboxProject = project(":mapbox_maps_flutter")
val originalScript = mapboxProject.projectDir.resolve("build.gradle")
val originalText = originalScript.readText().replace("\r\n", "\n")
val legacyKotlinBlock = """
    // Kotlin is built into AGP 9+. For older AGP (Flutter < 3.44) the
    // 'kotlin-android' plugin must still be applied explicitly.
    def agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.tokenize('.')[0] as int
    if (agpMajor < 9) {
        apply plugin: 'kotlin-android'
    }
""".trimIndent()

if (originalText.contains(legacyKotlinBlock)) {
    val migratedText = originalText.replace(
        legacyKotlinBlock,
        "// Kotlin integrado ao AGP 9; este aplicativo não usa o plugin Kotlin Android legado.",
    )
    val generatedScript = settingsDir.resolve(".gradle/mapbox-built-in-kotlin/build.gradle")
    generatedScript.parentFile.mkdirs()
    if (!generatedScript.exists() || generatedScript.readText() != migratedText) {
        generatedScript.writeText(migratedText)
    }

    // Mantém as fontes e os recursos no pacote original e altera só o script
    // de compilação deste projeto. A cópia acompanha o pacote resolvido pelo Pub.
    mapboxProject.buildFileName = generatedScript.relativeTo(mapboxProject.projectDir).path
} else {
    // Se o upstream já removeu o KGP, usa o script original. Se apenas mudou a
    // declaração antiga, pede revisão em vez de alterar código desconhecido.
    val legacyPlugin = Regex(
        """(?m)^\s*(?:apply\s+plugin\s*:|id\s*\(?)[ \t]*['"](?:kotlin-android|org\.jetbrains\.kotlin\.android)['"]""",
    )
    check(!legacyPlugin.containsMatchIn(originalText)) {
        "O script Android do Mapbox mudou. Revise gradle/mapbox-built-in-kotlin.settings.gradle.kts."
    }
}
