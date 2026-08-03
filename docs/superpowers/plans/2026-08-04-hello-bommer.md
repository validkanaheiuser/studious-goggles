# Hello Bommer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftUI iOS app with "Hello World" text and "OK Bommer" button (tap → alert), packaged as a fake-signed IPA via GitHub Actions CI for TrollStore installation.

**Architecture:** Single-screen SwiftUI app with a centered VStack. Xcode project is hand-crafted (no local Xcode required — all files are plain text). GitHub Actions uses a macOS runner to archive with xcodebuild, fake-sign with ldid, then upload the IPA as an artifact.

**Tech Stack:** Swift 5, SwiftUI (iOS 15+), xcodebuild, ldid, GitHub Actions (`macos-latest`)

## Global Constraints

- Deployment target: iOS 15.0
- Bundle ID: `com.local.hellobommer`
- No Apple Developer certificate or provisioning profile
- Signing: ldid fake-sign only (`ldid -S`)
- CI runner: `macos-latest`

---

### Task 1: Xcode project scaffold

**Files:**
- Create: `HelloBommer/HelloBommer.xcodeproj/project.pbxproj`
- Create: `HelloBommer/HelloBommer.xcodeproj/xcshareddata/xcschemes/HelloBommer.xcscheme`

**Interfaces:**
- Produces: Xcode project that references `HelloBommer/HelloBommerApp.swift` and `HelloBommer/ContentView.swift` (created in Task 2)

- [ ] **Step 1: Create project.pbxproj**

Create `HelloBommer/HelloBommer.xcodeproj/project.pbxproj` with this exact content:

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		BB0000000000000000000001 /* HelloBommerApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000002 /* HelloBommerApp.swift */; };
		BB0000000000000000000003 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000004 /* ContentView.swift */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		BB0000000000000000000005 /* HelloBommer.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HelloBommer.app; sourceTree = BUILT_PRODUCTS_DIR; };
		BB0000000000000000000002 /* HelloBommerApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = HelloBommerApp.swift; sourceTree = "<group>"; };
		BB0000000000000000000004 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		BB0000000000000000000006 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		BB0000000000000000000007 /* HelloBommer */ = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000002 /* HelloBommerApp.swift */,
				BB0000000000000000000004 /* ContentView.swift */,
			);
			path = HelloBommer;
			sourceTree = "<group>";
		};
		BB0000000000000000000008 /* Products */ = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000005 /* HelloBommer.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		BB0000000000000000000009 = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000007 /* HelloBommer */,
				BB0000000000000000000008 /* Products */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		BB000000000000000000000A /* HelloBommer */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = BB000000000000000000000B /* Build configuration list for PBXNativeTarget "HelloBommer" */;
			buildPhases = (
				BB000000000000000000000C /* Sources */,
				BB0000000000000000000006 /* Frameworks */,
				BB000000000000000000000D /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = HelloBommer;
			productName = HelloBommer;
			productReference = BB0000000000000000000005 /* HelloBommer.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		BB000000000000000000000E /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					BB000000000000000000000A = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = BB000000000000000000000F /* Build configuration list for PBXProject "HelloBommer" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = BB0000000000000000000009;
			productRefGroup = BB0000000000000000000008 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				BB000000000000000000000A /* HelloBommer */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		BB000000000000000000000D /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		BB000000000000000000000C /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				BB0000000000000000000001 /* HelloBommerApp.swift in Sources */,
				BB0000000000000000000003 /* ContentView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		BB0000000000000000000010 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		BB0000000000000000000011 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		BB0000000000000000000012 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.hellobommer;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		BB0000000000000000000013 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.local.hellobommer;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		BB000000000000000000000B /* Build configuration list for PBXNativeTarget "HelloBommer" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BB0000000000000000000012 /* Debug */,
				BB0000000000000000000013 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		BB000000000000000000000F /* Build configuration list for PBXProject "HelloBommer" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				BB0000000000000000000010 /* Debug */,
				BB0000000000000000000011 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = BB000000000000000000000E /* Project object */;
}
```

- [ ] **Step 2: Create HelloBommer.xcscheme**

Create `HelloBommer/HelloBommer.xcodeproj/xcshareddata/xcschemes/HelloBommer.xcscheme`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "BB000000000000000000000A"
               BuildableName = "HelloBommer.app"
               BlueprintName = "HelloBommer"
               ReferencedContainer = "container:HelloBommer.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "BB000000000000000000000A"
            BuildableName = "HelloBommer.app"
            BlueprintName = "HelloBommer"
            ReferencedContainer = "container:HelloBommer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "BB000000000000000000000A"
            BuildableName = "HelloBommer.app"
            BlueprintName = "HelloBommer"
            ReferencedContainer = "container:HelloBommer.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: Commit**

```bash
git add HelloBommer/
git commit -m "feat: scaffold Xcode project"
```

---

### Task 2: SwiftUI source files

**Files:**
- Create: `HelloBommer/HelloBommer/HelloBommerApp.swift`
- Create: `HelloBommer/HelloBommer/ContentView.swift`

**Interfaces:**
- Consumes: Xcode project from Task 1 (references exactly these two paths under the `HelloBommer` group)
- Produces: App entry point + single-screen UI with centered VStack and alert

- [ ] **Step 1: Create HelloBommerApp.swift**

Create `HelloBommer/HelloBommer/HelloBommerApp.swift`:

```swift
import SwiftUI

@main
struct HelloBommerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- [ ] **Step 2: Create ContentView.swift**

Create `HelloBommer/HelloBommer/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Hello World")
                .font(.largeTitle)
            Button("OK Bommer") {
                showAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Hello", isPresented: $showAlert) {
            Button("OK") {}
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add HelloBommer/HelloBommer/
git commit -m "feat: add SwiftUI source files"
```

---

### Task 3: GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Xcode project at `HelloBommer/HelloBommer.xcodeproj`, scheme name `HelloBommer`
- Produces: `HelloBommer.ipa` uploaded as a GitHub Actions artifact (retained 90 days)

- [ ] **Step 1: Create build.yml**

Create `.github/workflows/build.yml`:

```yaml
name: Build IPA

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build archive
        run: |
          xcodebuild archive \
            -project HelloBommer/HelloBommer.xcodeproj \
            -scheme HelloBommer \
            -configuration Release \
            -archivePath "$RUNNER_TEMP/HelloBommer.xcarchive" \
            -destination 'generic/platform=iOS' \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGN_IDENTITY=""

      - name: Install ldid
        run: brew install ldid

      - name: Fake-sign with ldid
        run: |
          APP="$RUNNER_TEMP/HelloBommer.xcarchive/Products/Applications/HelloBommer.app"
          ldid -S "$APP/HelloBommer"

      - name: Package IPA
        run: |
          mkdir -p "$RUNNER_TEMP/Payload"
          cp -r "$RUNNER_TEMP/HelloBommer.xcarchive/Products/Applications/HelloBommer.app" \
            "$RUNNER_TEMP/Payload/HelloBommer.app"
          cd "$RUNNER_TEMP"
          zip -r HelloBommer.ipa Payload

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: HelloBommer
          path: ${{ runner.temp }}/HelloBommer.ipa
          retention-days: 90
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/build.yml
git commit -m "ci: add GitHub Actions IPA build workflow"
git push origin main
```

- [ ] **Step 3: Verify CI**

Go to the GitHub repo → **Actions** tab → watch the `Build IPA` workflow. Should complete in ~5–10 minutes. When green, download the `HelloBommer` artifact zip, extract `HelloBommer.ipa`, and install via TrollStore.
