allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Força Java 11 para todos os subprojetos (app + plugins)
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_11.toString()
        targetCompatibility = JavaVersion.VERSION_11.toString()
        options.encoding = "UTF-8"
    }

    afterEvaluate {
        extensions.findByType<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension>()?.apply {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
        }
    }
}

// Configurações globais para evitar problemas de daemon
tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions {
        jvmTarget = "11"
    }
}
