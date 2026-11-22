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

// Workaround: the transitive `jni` plugin library (via path_provider_android) fails
// AAPT resource verification against androidx core on AGP 9.x. It ships no UI
// resources of its own, so skipping its release resource verification is safe.
subprojects {
    if (project.name == "jni") {
        tasks.configureEach {
            if (name == "verifyReleaseResources") enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
