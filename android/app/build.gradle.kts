import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

// ── تحذيرٌ صاخب حين يغيب مفتاح التوقيع ────────────────────────────
//
// 🐛 بلاغ المستخدم ٢٠٢٦-٠٩-٠٤: «يطلع لي خطأ بالـkey» عند الرفع لـPlay.
//
// السبب أنّ `buildTypes.release` أدناه يسقط إلى `signingConfigs.debug`
// حين لا يوجد `key.properties` — **بلا أيّ رسالة**. فيخرج ملفٌّ اسمه
// release وتوقيعُه تجريبيّ، وGoogle يرفضه بعد رفعٍ كامل.
//
// ولا نُفشل البناء: بناء APK للتجربة على خادمٍ بلا مفتاح استعمالٌ
// مشروع. لكنّ الصمت هو المشكلة — فنصرخ ويبقى الخيار للبانِي.
if (!keystorePropertiesFile.exists()) {
    logger.warn("")
    logger.warn("█".repeat(66))
    logger.warn("█  ⚠️  android/key.properties غير موجود")
    logger.warn("█  بناء release سيُوقَّع بمفتاح **debug** — وGoogle Play يرفضه.")
    logger.warn("█  صالحٌ للتجربة والتثبيت المباشر فقط، لا للرفع.")
    logger.warn("█")
    logger.warn("█  للرفع: أنشئ android/key.properties بالمفاتيح الأربعة")
    logger.warn("█  keyAlias · keyPassword · storeFile · storePassword")
    logger.warn("█".repeat(66))
    logger.warn("")
}

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.mysvcs.rad_mysvcs"
    // 2026-07-13 (v2): plugins الجديدة (url_launcher, local_auth,
    // speech_to_text, shared_preferences، إلخ) صارت تتطلّب compileSdk 36
    // و NDK 28+. Google Play 16 KB page size مدعوم تلقائياً من NDK 27+
    // فـ28 يغطّيه أيضاً.
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "com.mysvcs.rad_mysvcs"
        minSdk = flutter.minSdkVersion
        // targetSdk 36 = Android 16 (متطلَّب Play بعد أغسطس 2026 للتطبيقات
        // الجديدة). التحديثات الحاليّة لا تزال 35 لكن نستبق لضمان لا رفض.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Kotlin 2.2 رفع إهمال `kotlinOptions` إلى مستوى ERROR في سكربتات
// .kts. هذا هو البديل الرسمي المستعمل في قالب Flutter 3.47 نفسه.
// JVM_11 مُبقىً كما كان — رفعه إلى 17 حركة زائدة تمسّ desugaring
// وتوافق الحزم بلا داعٍ.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
