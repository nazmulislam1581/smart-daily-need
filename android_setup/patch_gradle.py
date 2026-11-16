"""flutter create এর পরে android/app/build.gradle(.kts)-এ desugaring যোগ করে।"""
import pathlib, re, sys

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")
f = kts if kts.exists() else groovy
src = f.read_text()
if "desugar_jdk_libs" in src:
    sys.exit(0)

if f is kts:
    src = re.sub(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", src, count=1)
    src += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
else:
    src = re.sub(r"compileOptions\s*\{", "compileOptions {\n        coreLibraryDesugaringEnabled true", src, count=1)
    src += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
f.write_text(src)
print("patched", f)
