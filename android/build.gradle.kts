allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    if (project.name == "tflite_flutter") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }
    
    // Inject namespace into legacy plugins like ffmpeg_kit_flutter
    if (project.name.contains("ffmpeg_kit_flutter")) {
        project.buildscript {
            project.extensions.extraProperties.set("namespace", "com.arthenica.ffmpegkit.flutter")
        }
        
        project.afterEvaluate {
            val androidExtension = project.extensions.findByName("android")
            if (androidExtension != null) {
                try {
                    val getNamespace = androidExtension.javaClass.getMethod("getNamespace")
                    val namespace = getNamespace.invoke(androidExtension)
                    if (namespace == null || namespace.toString().isEmpty()) {
                        val setNamespace = androidExtension.javaClass.getMethod("setNamespace", String::class.java)
                        setNamespace.invoke(androidExtension, "com.arthenica.ffmpegkit.flutter")
                    }
                } catch (e: Exception) {
                    println("Failed to set namespace for ${project.name}: ${e.message}")
                }
            }
        }
    }
}
