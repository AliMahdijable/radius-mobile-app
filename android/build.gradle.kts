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

// 2026-07-13: flutter_app_badger 1.5.0 (وبعض plugins القديمة) ماكو
// عندها `namespace` في build.gradle الخاصّها. AGP 8+ يرفض البناء بدونه.
// نُوسمها تلقائياً بـpackage الـplugin (group + name) — نظيف بدون ما
// نلمس ملفات pub cache. https://github.com/flutter/flutter/issues/144614
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library") ||
            plugins.hasPlugin("com.android.application")) {
            extensions.findByName("android")?.let { android ->
                val ns = android.javaClass.getMethod("getNamespace").invoke(android) as String?
                if (ns.isNullOrBlank()) {
                    val fallback = (group?.toString()?.takeIf { it.isNotBlank() }
                        ?: "com.patched.${project.name.replace('-', '_')}")
                    android.javaClass.getMethod("setNamespace", String::class.java)
                        .invoke(android, fallback)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
