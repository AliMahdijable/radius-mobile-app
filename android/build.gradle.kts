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
// نُوسمها تلقائياً بـpackage الـplugin — نظيف بدون ما نلمس ملفات pub
// cache. Ref: flutter/flutter#144614.
//
// نستعمل plugins.withId (يشتغل فوراً لما يُطبَّق الـAndroid plugin،
// قبل ما LibraryVariantBuilder يُنشأ ويقرأ namespace) — أدقّ من
// afterEvaluate الذي يتأخّر أحياناً. الـreflection يتفادى الاعتماد
// المباشر على AGP classpath في هذا السكربت.
subprojects {
    // plugins.withId يشتغل فوراً لما يُطبَّق الـplugin — لا نحتاج
    // afterEvaluate (يرمي "already evaluated" لبعض الـsubprojects
    // التي انتهت مبكراً بسبب evaluationDependsOn(":app") أعلاه).
    plugins.withId("com.android.library") { fixNamespace(); fixCompileSdk() }
    plugins.withId("com.android.application") { fixNamespace(); fixCompileSdk() }
}

fun Project.fixNamespace() {
    val android = extensions.findByName("android") ?: return
    try {
        val get = android.javaClass.getMethod("getNamespace")
        val current = get.invoke(android) as String?
        if (current.isNullOrBlank()) {
            val fallback = "com.patched.${project.name.replace('-', '_').replace('.', '_')}"
            android.javaClass.getMethod("setNamespace", String::class.java)
                .invoke(android, fallback)
            println("🔧 [patched-namespace] ${project.name} → $fallback")
        }
    } catch (_: Throwable) { /* method missing on old AGP = safe skip */ }
}

// 2026-08-12: بعض plugins القديمة (flutter_app_badger_plus مثلاً) تستعمل
// compileSdk < 31 → مما يفشل resource linking لأن android:attr/lStar
// أُضيف في API 31 (Android 12) وموجود في androidx.core:core:1.7.0+.
// الرسالة: "resource android:attr/lStar not found".
// الحل: نُجبر compileSdk = 34 على كل plugin بـcompileSdk أقل من 34.
fun Project.fixCompileSdk() {
    val android = extensions.findByName("android") ?: return
    try {
        val get = android.javaClass.getMethod("getCompileSdk")
        val current = get.invoke(android) as Int?
        if (current == null || current < 34) {
            android.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                .invoke(android, 34)
            println("🔧 [patched-compileSdk] ${project.name}: $current → 34")
        }
    } catch (_: Throwable) { /* API might differ across AGP versions */ }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
