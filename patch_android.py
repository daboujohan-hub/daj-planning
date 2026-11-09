import re
import sys
import pathlib

root = pathlib.Path(sys.argv[1])

# ---------- AndroidManifest : permissions + récepteurs d'alarmes ----------
man = root / "app/src/main/AndroidManifest.xml"
t = man.read_text()

perms = """<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
"""

receivers = """<receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""

assert "<application" in t and "</application>" in t, "Manifest inattendu"
t = t.replace("<application", perms + "    <application android:allowBackup=\"false\"", 1)
t = re.sub(r'android:label="[^"]*"', 'android:label="DAJ Planning"', t, count=1)
t = t.replace("</application>", receivers + "    </application>", 1)
man.write_text(t)

# ---------- Gradle : desugaring requis par les notifications ----------
kts = root / "app/build.gradle.kts"
groovy = root / "app/build.gradle"

if kts.exists():
    g = kts.read_text()
    g, n = re.subn(r"(compileOptions\s*\{)",
                   r"\1\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    assert n == 1, "compileOptions introuvable (kts)"
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    kts.write_text(g)
elif groovy.exists():
    g = groovy.read_text()
    g, n = re.subn(r"(compileOptions\s*\{)",
                   r"\1\n        coreLibraryDesugaringEnabled true", g, count=1)
    assert n == 1, "compileOptions introuvable (groovy)"
    g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    groovy.write_text(g)
else:
    raise SystemExit("build.gradle introuvable")

print("Patch Android OK")
