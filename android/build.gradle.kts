allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Supply-chain (phase 071 audit, MEDIUM): image_cropper's own build.gradle adds
// an UNFILTERED `maven { jitpack.io }` to every project. JitPack builds from
// arbitrary GitHub tags, so any artifact name could resolve from it. Restrict
// every jitpack repo to the single group ucrop needs. Evaluated AFTER all
// projects are configured, i.e. after the plugin has added its repository.
gradle.projectsEvaluated {
    allprojects {
        repositories.withType<MavenArtifactRepository>().configureEach {
            if (url.host == "jitpack.io") {
                content { includeGroup("com.github.Yalantis") }
            }
        }
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

// Suppress the JDK "source/target value 8 is obsolete" note emitted by
// third-party plugin modules that still pin Java 8 (e.g. patrol 4.6.1).
// Cosmetic-only: does NOT change bytecode target, desugaring, or Kotlin jvmTarget.
subprojects {
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
