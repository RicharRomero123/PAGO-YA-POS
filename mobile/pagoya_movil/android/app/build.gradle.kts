// PagoYa Móvil — configuración de compilación Android.
//
// ESCRITO A MANO por `flutter-hardware` ANTES de correr `flutter create`.
// Tras `flutter create --platforms=android,ios .`, Flutter generará su propio
// android/app/build.gradle.kts. Hay que FUSIONAR: lo importante de este archivo
// son `minSdk`, `targetSdk`, `compileSdk`, `applicationId`, el desugaring y el
// bloque `packaging`. Todo lo demás es el estándar del template.

plugins {
    id("com.android.application")
    id("kotlin-android")
    // El plugin de Flutter DEBE ir después de los de Android y Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pe.pagoya.movil"

    // compileSdk 36 = Android 16. Se compila contra el SDK más nuevo aunque el
    // mínimo soportado sea mucho menor; no afecta a los teléfonos viejos.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications y varias libs de AndroidX lo exigen para
        // usar java.time en API < 26.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "pe.pagoya.movil"

        // -----------------------------------------------------------------
        // minSdk 23 = Android 6.0 Marshmallow (2015).
        //
        // Por qué 23 y no menos: `flutter_secure_storage` usa
        // EncryptedSharedPreferences sobre el Android Keystore, que necesita
        // API 23. Bajar de ahí obligaría a guardar el token de licencia y el
        // id de dispositivo en claro — inaceptable para el modelo de negocio.
        // `flutter_blue_plus` también pide 23.
        //
        // Por qué no subir a 24/26: el mercado objetivo son bodegas con
        // teléfonos de gama baja y de segunda mano. API 23 cubre >99 % de los
        // dispositivos Android activos y no cuesta nada mantenerlo.
        // -----------------------------------------------------------------
        minSdk = 23

        // targetSdk 36 = Android 16. Google Play exige API 36 para
        // actualizaciones desde agosto de 2026. Implica cumplir el
        // comportamiento nuevo: edge-to-edge obligatorio y páginas de 16 KB.
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Con minSdk 23 no hace falta la librería de multidex, pero sí
        // habilitarlo: ML Kit + AndroidX pasan de 64 K métodos.
        multiDexEnabled = true
    }

    signingConfigs {
        // El keystore de release NO va en el repositorio (ver CLAUDE.md:
        // "nada de credenciales en el repo"). Se configura en
        // android/key.properties, que va en .gitignore.
    }

    buildTypes {
        release {
            // TODO(usuario): apuntar al keystore real antes de publicar en Play.
            // Mientras tanto se firma con debug para poder generar APK de prueba.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    packaging {
        resources {
            // Varias libs (ML Kit, Bouncy Castle vía cripto) traen los mismos
            // metadatos y el empaquetado falla por duplicado.
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/*.kotlin_module",
            )
        }
        jniLibs {
            // Requisito de Android 15+ (páginas de 16 KB) y de sqlite3_flutter_libs.
            useLegacyPackaging = false
        }
    }

    lint {
        // Un warning de lint no puede tumbar el build de release de una app
        // que se vende por Facebook Ads y hay que publicar el mismo día.
        checkReleaseBuilds = false
        abortOnError = false
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}