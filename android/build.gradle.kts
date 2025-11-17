allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Força Java 11 para TODOS os projetos e plugins
allprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-Xlint:-options"))
    }

    afterEvaluate {
        // Kotlin JVM target usando compilerOptions (sintaxe moderna)
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }

        // Força Java 11 em todas as extensões Android
        extensions.findByType<com.android.build.gradle.BaseExtension>()?.apply {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_11
                targetCompatibility = JavaVersion.VERSION_11
            }
        }
    }
}
