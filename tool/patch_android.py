"""Ajusta android/app/build.gradle.kts generado por `flutter create`:
minSdk 26 (Health Connect), desugaring (notificaciones), firma fija y reglas ProGuard."""
import pathlib, re, sys

f = pathlib.Path('android/app/build.gradle.kts')
s = f.read_text()
orig = s

def sub(pattern, repl, desc, count=1):
    global s
    new, n = re.subn(pattern, repl, s, count=count)
    if n == 0:
        print(f'::error::No se encontró: {desc}')
        print(s)
        sys.exit(1)
    s = new

if 'isCoreLibraryDesugaringEnabled' not in s:
    sub(r'minSdk\s*=\s*[^\n]+', 'minSdk = 26', 'minSdk')
    sub(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 'compileOptions')
    sub(r'(\n\s*)buildTypes\s*\{', r'''\1signingConfigs {
        create("release") {
            storeFile = file("release.jks")
            storePassword = "balance-fernando"
            keyAlias = "balance"
            keyPassword = "balance-fernando"
        }
    }
\1buildTypes {''', 'buildTypes')
    sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = signingConfigs.getByName("release")\n            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")',
        'signingConfig debug')
    s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'

f.write_text(s)
print(s)
