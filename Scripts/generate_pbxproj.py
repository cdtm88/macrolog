#!/usr/bin/env python3
"""Generate MacroLog.xcodeproj/project.pbxproj (app + widget targets).

This is a fallback generator so the project opens without XcodeGen installed.
`project.yml` is the canonical definition — `xcodegen generate` reproduces an
equivalent project. Run this from the repo root:  python3 Scripts/generate_pbxproj.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

_counter = [0]
def uid():
    _counter[0] += 1
    return f"{_counter[0]:024X}"

def swift_files(*dirs):
    out = []
    for d in dirs:
        for base, _, files in sorted(os.walk(d)):
            for f in sorted(files):
                if f.endswith(".swift"):
                    out.append(os.path.join(base, f))
    return out

APP_SRC = swift_files("MacroLog") + swift_files("MacroLogShared")
WIDGET_SRC = swift_files("MacroLogWidget") + swift_files("MacroLogShared")

# --- object id registries ---
fileRefs = {}   # path -> id
def ref(path):
    if path not in fileRefs:
        fileRefs[path] = uid()
    return fileRefs[path]

# Products
appProductRef = uid()
widgetProductRef = uid()

# Assets / config extra refs
appAssets = "MacroLog/Assets.xcassets"; ref(appAssets)
widgetAssets = "MacroLogWidget/Assets.xcassets"; ref(widgetAssets)
appInfo = "MacroLog/Resources/Info.plist"; ref(appInfo)
appEnt = "MacroLog/Resources/MacroLog.entitlements"; ref(appEnt)
widgetInfo = "MacroLogWidget/Info.plist"; ref(widgetInfo)
widgetEnt = "MacroLogWidget/MacroLogWidget.entitlements"; ref(widgetEnt)
secretsCfg = "MacroLog/Config/Secrets.xcconfig"; ref(secretsCfg)
secretsExample = "MacroLog/Config/Secrets.example.xcconfig"; ref(secretsExample)
for p in APP_SRC + WIDGET_SRC:
    ref(p)

# Build files (path, target) -> id
appBuild = {p: uid() for p in APP_SRC}
appBuild[appAssets] = uid()
widgetBuild = {p: uid() for p in WIDGET_SRC}
widgetBuild[widgetAssets] = uid()
embedWidgetBuild = uid()

# Targets, phases, config lists
appTarget = uid(); widgetTarget = uid(); projectObj = uid()
appSourcesPhase = uid(); appFrameworksPhase = uid(); appResourcesPhase = uid(); appEmbedPhase = uid()
widgetSourcesPhase = uid(); widgetFrameworksPhase = uid(); widgetResourcesPhase = uid()
projCfgList = uid(); appCfgList = uid(); widgetCfgList = uid()
projDebug = uid(); projRelease = uid()
appDebug = uid(); appRelease = uid()
widgetDebug = uid(); widgetRelease = uid()
containerProxy = uid(); targetDep = uid()

# Groups
mainGroup = uid(); productsGroup = uid()
appGroup = uid(); sharedGroup = uid(); widgetGroup = uid()

def filetype(path):
    if path.endswith(".swift"): return "sourcecode.swift"
    if path.endswith(".xcassets"): return "folder.assetcatalog"
    if path.endswith(".plist"): return "text.plist.xml"
    if path.endswith(".entitlements"): return "text.plist.entitlements"
    if path.endswith(".xcconfig"): return "text.xcconfig"
    return "text"

def relto(path, root):
    return os.path.relpath(path, root)

lines = []
def w(s=""): lines.append(s)

w("// !$*UTF8*$!")
w("{")
w("\tarchiveVersion = 1;")
w("\tclasses = {};")
w("\tobjectVersion = 56;")
w("\tobjects = {")

# PBXBuildFile
w("\n/* Begin PBXBuildFile section */")
for p in APP_SRC:
    w(f"\t\t{appBuild[p]} /* {os.path.basename(p)} */ = {{isa = PBXBuildFile; fileRef = {ref(p)} /* {os.path.basename(p)} */; }};")
w(f"\t\t{appBuild[appAssets]} /* Assets.xcassets */ = {{isa = PBXBuildFile; fileRef = {ref(appAssets)} /* Assets.xcassets */; }};")
for p in WIDGET_SRC:
    w(f"\t\t{widgetBuild[p]} /* {os.path.basename(p)} */ = {{isa = PBXBuildFile; fileRef = {ref(p)} /* {os.path.basename(p)} */; }};")
w(f"\t\t{widgetBuild[widgetAssets]} /* Assets.xcassets */ = {{isa = PBXBuildFile; fileRef = {ref(widgetAssets)} /* Assets.xcassets */; }};")
w(f"\t\t{embedWidgetBuild} /* MacroLogWidget.appex */ = {{isa = PBXBuildFile; fileRef = {widgetProductRef} /* MacroLogWidget.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
w("/* End PBXBuildFile section */")

# PBXContainerItemProxy
w("\n/* Begin PBXContainerItemProxy section */")
w(f"\t\t{containerProxy} /* PBXContainerItemProxy */ = {{")
w("\t\t\tisa = PBXContainerItemProxy;")
w(f"\t\t\tcontainerPortal = {projectObj} /* Project object */;")
w("\t\t\tproxyType = 1;")
w(f"\t\t\tremoteGlobalIDString = {widgetTarget};")
w("\t\t\tremoteInfo = MacroLogWidget;")
w("\t\t};")
w("/* End PBXContainerItemProxy section */")

# PBXCopyFilesBuildPhase (embed)
w("\n/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{appEmbedPhase} /* Embed Foundation Extensions */ = {{")
w("\t\t\tisa = PBXCopyFilesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tdstPath = \"\";")
w("\t\t\tdstSubfolderSpec = 13;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{embedWidgetBuild} /* MacroLogWidget.appex */,")
w("\t\t\t);")
w("\t\t\tname = \"Embed Foundation Extensions\";")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXCopyFilesBuildPhase section */")

# PBXFileReference
w("\n/* Begin PBXFileReference section */")
w(f"\t\t{appProductRef} /* MacroLog.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacroLog.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
w(f"\t\t{widgetProductRef} /* MacroLogWidget.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = MacroLogWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
def emit_ref(path, group_root):
    rel = relto(path, group_root)
    w(f"\t\t{ref(path)} /* {os.path.basename(path)} */ = {{isa = PBXFileReference; lastKnownFileType = {filetype(path)}; name = \"{os.path.basename(path)}\"; path = \"{rel}\"; sourceTree = \"<group>\"; }};")
# app group members
for p in swift_files("MacroLog"): emit_ref(p, "MacroLog")
emit_ref(appAssets, "MacroLog"); emit_ref(appInfo, "MacroLog"); emit_ref(appEnt, "MacroLog")
emit_ref(secretsCfg, "MacroLog"); emit_ref(secretsExample, "MacroLog")
# shared group
for p in swift_files("MacroLogShared"): emit_ref(p, "MacroLogShared")
# widget group
for p in swift_files("MacroLogWidget"): emit_ref(p, "MacroLogWidget")
emit_ref(widgetAssets, "MacroLogWidget"); emit_ref(widgetInfo, "MacroLogWidget"); emit_ref(widgetEnt, "MacroLogWidget")
w("/* End PBXFileReference section */")

# PBXFrameworksBuildPhase
w("\n/* Begin PBXFrameworksBuildPhase section */")
for pid in (appFrameworksPhase, widgetFrameworksPhase):
    w(f"\t\t{pid} /* Frameworks */ = {{")
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
w("/* End PBXFrameworksBuildPhase section */")

# PBXGroup
w("\n/* Begin PBXGroup section */")
w(f"\t\t{mainGroup} = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
for g in (appGroup, sharedGroup, widgetGroup, productsGroup):
    w(f"\t\t\t\t{g},")
w("\t\t\t);")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

w(f"\t\t{productsGroup} /* Products */ = {{")
w("\t\t\tisa = PBXGroup;")
w("\t\t\tchildren = (")
w(f"\t\t\t\t{appProductRef} /* MacroLog.app */,")
w(f"\t\t\t\t{widgetProductRef} /* MacroLogWidget.appex */,")
w("\t\t\t);")
w("\t\t\tname = Products;")
w("\t\t\tsourceTree = \"<group>\";")
w("\t\t};")

def emit_group(gid, name, path, members):
    w(f"\t\t{gid} /* {name} */ = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for m in members:
        w(f"\t\t\t\t{ref(m)} /* {os.path.basename(m)} */,")
    w("\t\t\t);")
    w(f"\t\t\tpath = {path};")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

emit_group(appGroup, "MacroLog", "MacroLog",
           swift_files("MacroLog") + [appAssets, appInfo, appEnt, secretsCfg, secretsExample])
emit_group(sharedGroup, "MacroLogShared", "MacroLogShared", swift_files("MacroLogShared"))
emit_group(widgetGroup, "MacroLogWidget", "MacroLogWidget",
           swift_files("MacroLogWidget") + [widgetAssets, widgetInfo, widgetEnt])
w("/* End PBXGroup section */")

# PBXNativeTarget
w("\n/* Begin PBXNativeTarget section */")
w(f"\t\t{appTarget} /* MacroLog */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {appCfgList};")
w("\t\t\tbuildPhases = (")
for ph in (appSourcesPhase, appFrameworksPhase, appResourcesPhase, appEmbedPhase):
    w(f"\t\t\t\t{ph},")
w("\t\t\t);")
w("\t\t\tbuildRules = ();")
w("\t\t\tdependencies = (")
w(f"\t\t\t\t{targetDep},")
w("\t\t\t);")
w("\t\t\tname = MacroLog;")
w("\t\t\tproductName = MacroLog;")
w(f"\t\t\tproductReference = {appProductRef} /* MacroLog.app */;")
w("\t\t\tproductType = \"com.apple.product-type.application\";")
w("\t\t};")

w(f"\t\t{widgetTarget} /* MacroLogWidget */ = {{")
w("\t\t\tisa = PBXNativeTarget;")
w(f"\t\t\tbuildConfigurationList = {widgetCfgList};")
w("\t\t\tbuildPhases = (")
for ph in (widgetSourcesPhase, widgetFrameworksPhase, widgetResourcesPhase):
    w(f"\t\t\t\t{ph},")
w("\t\t\t);")
w("\t\t\tbuildRules = ();")
w("\t\t\tdependencies = ();")
w("\t\t\tname = MacroLogWidget;")
w("\t\t\tproductName = MacroLogWidget;")
w(f"\t\t\tproductReference = {widgetProductRef} /* MacroLogWidget.appex */;")
w("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
w("\t\t};")
w("/* End PBXNativeTarget section */")

# PBXProject
w("\n/* Begin PBXProject section */")
w(f"\t\t{projectObj} /* Project object */ = {{")
w("\t\t\tisa = PBXProject;")
w("\t\t\tattributes = {")
w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
w("\t\t\t\tLastUpgradeCheck = 1600;")
w("\t\t\t\tTargetAttributes = {")
w(f"\t\t\t\t\t{appTarget} = {{CreatedOnToolsVersion = 16.0;}};")
w(f"\t\t\t\t\t{widgetTarget} = {{CreatedOnToolsVersion = 16.0;}};")
w("\t\t\t\t};")
w("\t\t\t};")
w(f"\t\t\tbuildConfigurationList = {projCfgList};")
w("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
w("\t\t\tdevelopmentRegion = en;")
w("\t\t\thasScannedForEncodings = 0;")
w("\t\t\tknownRegions = (en, Base);")
w(f"\t\t\tmainGroup = {mainGroup};")
w(f"\t\t\tproductRefGroup = {productsGroup} /* Products */;")
w("\t\t\tprojectDirPath = \"\";")
w("\t\t\tprojectRoot = \"\";")
w("\t\t\ttargets = (")
w(f"\t\t\t\t{appTarget} /* MacroLog */,")
w(f"\t\t\t\t{widgetTarget} /* MacroLogWidget */,")
w("\t\t\t);")
w("\t\t};")
w("/* End PBXProject section */")

# PBXResourcesBuildPhase
w("\n/* Begin PBXResourcesBuildPhase section */")
w(f"\t\t{appResourcesPhase} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{appBuild[appAssets]} /* Assets.xcassets */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{widgetResourcesPhase} /* Resources */ = {{")
w("\t\t\tisa = PBXResourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
w(f"\t\t\t\t{widgetBuild[widgetAssets]} /* Assets.xcassets */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXResourcesBuildPhase section */")

# PBXSourcesBuildPhase
w("\n/* Begin PBXSourcesBuildPhase section */")
w(f"\t\t{appSourcesPhase} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in APP_SRC:
    w(f"\t\t\t\t{appBuild[p]} /* {os.path.basename(p)} */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w(f"\t\t{widgetSourcesPhase} /* Sources */ = {{")
w("\t\t\tisa = PBXSourcesBuildPhase;")
w("\t\t\tbuildActionMask = 2147483647;")
w("\t\t\tfiles = (")
for p in WIDGET_SRC:
    w(f"\t\t\t\t{widgetBuild[p]} /* {os.path.basename(p)} */,")
w("\t\t\t);")
w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
w("\t\t};")
w("/* End PBXSourcesBuildPhase section */")

# PBXTargetDependency
w("\n/* Begin PBXTargetDependency section */")
w(f"\t\t{targetDep} /* PBXTargetDependency */ = {{")
w("\t\t\tisa = PBXTargetDependency;")
w("\t\t\ttarget = " + widgetTarget + " /* MacroLogWidget */;")
w(f"\t\t\ttargetProxy = {containerProxy} /* PBXContainerItemProxy */;")
w("\t\t};")
w("/* End PBXTargetDependency section */")

# XCBuildConfiguration
def emit_cfg(cid, name, settings):
    w(f"\t\t{cid} /* {name} */ = {{")
    w("\t\t\tisa = XCBuildConfiguration;")
    w("\t\t\tbuildSettings = {")
    for k in sorted(settings):
        v = settings[k]
        w(f"\t\t\t\t{k} = {v};")
    w("\t\t\t};")
    w(f"\t\t\tname = {name};")
    w("\t\t};")

PROJ_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "MARKETING_VERSION": "1.0",
    "CURRENT_PROJECT_VERSION": "1",
}
emit_cfg(projDebug, "Debug", {**PROJ_COMMON,
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": "\"DEBUG=1\"",
    "MTL_FAST_MATH": "YES",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "\"DEBUG $(inherited)\"",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\"",
})
emit_cfg(projRelease, "Release", {**PROJ_COMMON,
    "DEBUG_INFORMATION_FORMAT": "\"dwarf-with-dsym\"",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_FAST_MATH": "YES",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "\"-O\"",
    "VALIDATE_PRODUCT": "YES",
})

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "MacroLog/Resources/MacroLog.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "MacroLog/Resources/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "LD_RUNPATH_SEARCH_PATHS": "\"$(inherited) @executable_path/Frameworks\"",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.macrolog.app",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}
emit_cfg(appDebug, "Debug", dict(APP_COMMON))
emit_cfg(appRelease, "Release", dict(APP_COMMON))

WIDGET_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "MacroLogWidget/MacroLogWidget.entitlements",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "MacroLogWidget/Info.plist",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "LD_RUNPATH_SEARCH_PATHS": "\"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks\"",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.macrolog.app.widget",
    "PRODUCT_NAME": "\"$(TARGET_NAME)\"",
    "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}
emit_cfg(widgetDebug, "Debug", dict(WIDGET_COMMON))
emit_cfg(widgetRelease, "Release", dict(WIDGET_COMMON))

# XCConfigurationList
w("\n/* Begin XCConfigurationList section */")
def emit_cfglist(cid, name, debug, release, default="Release"):
    w(f"\t\t{cid} /* Build configuration list for {name} */ = {{")
    w("\t\t\tisa = XCConfigurationList;")
    w("\t\t\tbuildConfigurations = (")
    w(f"\t\t\t\t{debug} /* Debug */,")
    w(f"\t\t\t\t{release} /* Release */,")
    w("\t\t\t);")
    w("\t\t\tdefaultConfigurationIsVisible = 0;")
    w(f"\t\t\tdefaultConfigurationName = {default};")
    w("\t\t};")
emit_cfglist(projCfgList, "PBXProject", projDebug, projRelease)
emit_cfglist(appCfgList, "PBXNativeTarget \"MacroLog\"", appDebug, appRelease)
emit_cfglist(widgetCfgList, "PBXNativeTarget \"MacroLogWidget\"", widgetDebug, widgetRelease)
w("/* End XCConfigurationList section */")

w("\t};")
w(f"\trootObject = {projectObj} /* Project object */;")
w("}")

os.makedirs("MacroLog.xcodeproj", exist_ok=True)
with open("MacroLog.xcodeproj/project.pbxproj", "w") as f:
    f.write("\n".join(lines) + "\n")

# Baseconfiguration wiring: attach Secrets.xcconfig to app Debug/Release.
# (Injected post-hoc so the two XCBuildConfiguration dicts carry it.)
content = open("MacroLog.xcodeproj/project.pbxproj").read()
for cid in (appDebug, appRelease):
    needle = f"\t\t{cid} /* "
    idx = content.index(needle)
    insert_at = content.index("isa = XCBuildConfiguration;", idx) + len("isa = XCBuildConfiguration;")
    inject = f"\n\t\t\tbaseConfigurationReference = {ref(secretsCfg)} /* Secrets.xcconfig */;"
    content = content[:insert_at] + inject + content[insert_at:]
open("MacroLog.xcodeproj/project.pbxproj", "w").write(content)

# Shared scheme
os.makedirs("MacroLog.xcodeproj/xcshareddata/xcschemes", exist_ok=True)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="MacroLog.app" BlueprintName="MacroLog" ReferencedContainer="container:MacroLog.xcodeproj"></BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="MacroLog.app" BlueprintName="MacroLog" ReferencedContainer="container:MacroLog.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{appTarget}" BuildableName="MacroLog.app" BlueprintName="MacroLog" ReferencedContainer="container:MacroLog.xcodeproj"></BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"></ArchiveAction>
</Scheme>
'''
open("MacroLog.xcodeproj/xcshareddata/xcschemes/MacroLog.xcscheme", "w").write(scheme)

print(f"Generated project with {len(APP_SRC)} app sources, {len(WIDGET_SRC)} widget sources.")
