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
    plugins.withId("com.android.library") { fixNamespace() }
    plugins.withId("com.android.application") { fixNamespace() }

    // compileSdk يُضبط داخل الـandroid {} block الي في build.gradle الـplugin
    // نفسه — بعد plugins.withId. لهذا نستعمل afterEvaluate.
    //
    // مشكلة: evaluationDependsOn(":app") أعلاه يُنهي evaluation لبعض
    // الـsubprojects مبكراً — وقت وصولنا هنا state.executed = true،
    // وإضافة afterEvaluate يرمي "already evaluated". الحل: نفحص state
    // ونشغّل مباشرة لو انتهى، وإلا نسجّل callback.
    if (state.executed) {
        fixCompileSdk()
    } else {
        afterEvaluate { fixCompileSdk() }
    }
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
//
// نُشغّلها في afterEvaluate — لأن الـandroid {} block في build.gradle الـplugin
// نفسه يضبط compileSdk بعد ما نصل هنا (لو استعملنا plugins.withId يُلغى تعديلنا).
//
// الـsetter في AGP الحديث (8.x+) يقبل Integer/int. reflection يحمينا من
// اختلافات AGP API عبر الإصدارات.
fun Project.fixCompileSdk() {
    val android = extensions.findByName("android") ?: return
    val target = 34
    try {
        val getMethod = android.javaClass.methods.firstOrNull { it.name == "getCompileSdk" }
        val current = getMethod?.invoke(android) as? Int

        if (current == null || current < target) {
            // setCompileSdk موجود بـ overloads: int, Integer — نجرّب كليهما.
            val setters = android.javaClass.methods.filter { it.name == "setCompileSdk" }
            var applied = false
            for (setter in setters) {
                try {
                    setter.invoke(android, target)
                    applied = true
                    break
                } catch (_: Throwable) { /* try next overload */ }
            }
            if (applied) {
                println("🔧 [patched-compileSdk] ${project.name}: $current → $target")
            } else {
                println("⚠️ [patched-compileSdk] ${project.name}: no setter matched (current=$current)")
            }
        }
    } catch (e: Throwable) {
        println("⚠️ [patched-compileSdk] ${project.name}: ${e.javaClass.simpleName}: ${e.message}")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
