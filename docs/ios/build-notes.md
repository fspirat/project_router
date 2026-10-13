# Stage 3: facts for the iOS build in GitHub Actions (checked 2026-10-13)

> **Справочный документ (этап 3, 13.10.2026).** Заметки о сборке iPhone-приложения в GitHub Actions: раннер macOS, Xcode,
> XcodeGen, подпись, загрузка в TestFlight, расход минут. Собраны по открытым источникам (readme runner-images, документация
> GitHub, форумы Apple; список в конце). Версии Xcode и образов меняются — перед правкой сверять с readme runner-images.
> Что сделано на самом деле — `.github/workflows/ios-testflight.yml`, `.github/workflows/ios-core-tests.yml`, `ios/project.yml`;
> **при расхождении прав код workflow** (а поведение приложения — код сервера `server/auth/*.php`, CGI роутера и `web/app.js`).
> Своей подписки Apple у владельца пока нет (13.10.2026), поэтому части про TestFlight и ключи App Store Connect — на будущее.
> Имена секретов ниже (`ASC_KEY_P8` и др.) — только имена; сами значения хранятся в секретах GitHub.
> Итог в workflow (не так, как советует §7): push в `ios/**` собирает только с меткой `[ios build]` (проверка) или `[ios ipa]`
> (файл `.ipa` без подписи, хранится 7 дней); кнопка Run workflow (галочки `upload`, `ipa`, выбор `signing`) и запуск раз в 2 месяца.
>
> *Reference (stage 3, 13.10.2026): research notes for the iOS build in GitHub Actions. The workflow files win on any disagreement.*

The sources are listed at the end, and each fact cites one in [n]. Facts marked **(verified)** come from primary sources: the runner-images readmes, github/docs and the Homebrew formula. Facts marked **(reports)** come from forums and blogs, so check them on the first run.

---

## 1. macOS runner, Xcode, SDK

**Label: `runs-on: macos-26`** (arm64, Apple Silicon). The runner-images README maps `macos-latest`, `macos-26` and `macos-26-xlarge` to the **macOS 26 Arm64** image, and the `-latest` label is used only for an OS image that is GA. So macOS 26 is GA. **(verified [1])**
- Use `macos-26` rather than `macos-latest`. `-latest` moves to a new OS "over 1-2 months" [1], and macOS 27 with Xcode 27 is already in public preview [3].
- Do not use `macos-26-intel` / `macos-26-large` / `-xlarge`. These are larger runners, billed even when you still have quota, and larger runners stay blocked until a payment method is added [6].
- `macos-15` (arm64) has Xcode 26.0.1–26.3, but its default is **16.4** [2b]. It is a poor choice.

**macOS 26 arm64 image** (Image Version 20260907.0351.1, macOS 26.6.2) **(verified [2])**:

| Xcode | Build | Path | Symlinks |
|---|---|---|---|
| **26.6 (default)** | 17F113 | `/Applications/Xcode_26.6.app` | `/Applications/Xcode_26.6.0.app`, `/Applications/Xcode.app` |
| 26.5 | 17F42 | `/Applications/Xcode_26.5.app` | `Xcode_26.5.0.app` |
| 26.4.1 | 17E202 | `/Applications/Xcode_26.4.1.app` | `Xcode_26.4.app` |
| 26.3 | 17C529 | `/Applications/Xcode_26.3.app` | `Xcode_26.3.0.app` |
| 26.2 | 17C52 | `/Applications/Xcode_26.2.app` | `Xcode_26.2.0.app` |
| 26.1.1 | 17B100 | `/Applications/Xcode_26.1.1.app` | `Xcode_26.1.app` |
| 26.0.1 | 17A400 | `/Applications/Xcode_26.0.1.app` | `Xcode_26.0.app` |

- iOS SDKs: `iphoneos26.0 / 26.1 / 26.2 / 26.4 / 26.5`. Xcode 26.5 and 26.6 both ship **iOS 26.5 SDK**. Simulator SDKs are the same set.
- Simulator runtimes: iOS 26.2, 26.4 and 26.5, each with iPhone 17 / 17 Pro / 17 Pro Max / 17e / Air and iPads.
- Policy: one major Xcode per macOS image, with all of its minors installed. A new patch release replaces the previous patch [1]. **Do not hard-code the patch version.** Select by glob.
- Also preinstalled: Homebrew 6.0.22, Ruby 3.4.10, Fastlane 2.239.0, CocoaPods 1.17.0, SwiftFormat 0.63.0, Xcodes 2.0.3, Xcode CLT 26.6 [2].

**Step to select the newest Xcode 26.x.** It uses `DEVELOPER_DIR` and needs no sudo. It skips the symlinks and fails clearly if nothing is found:
```yaml
- name: Select Xcode 26
  run: |
    set -eu
    XC=""
    for f in /Applications/Xcode_26*.app; do
      [ -d "$f" ] || continue
      [ -L "$f" ] && continue            # skip the Xcode_26.6.0.app / Xcode_26.4.app symlinks
      XC="$XC$f"$'\n'
    done
    XC=$(printf '%s' "$XC" | grep -E '/Xcode_26(\.[0-9]+){0,2}\.app$' | sort -V | tail -n 1)
    [ -n "$XC" ] || { echo "::error::Xcode 26 not found"; ls -d /Applications/Xcode* || true; exit 1; }
    echo "DEVELOPER_DIR=$XC/Contents/Developer" >> "$GITHUB_ENV"
    sudo xcode-select -s "$XC/Contents/Developer"   # optional; DEVELOPER_DIR is enough for xcodebuild/xcrun
    echo "Selected: $XC"
- name: Versions
  run: |
    xcodebuild -version
    xcrun --sdk iphoneos --show-sdk-version
    xcrun --sdk iphoneos --show-sdk-path
    swift --version
    sw_vers
```
`sort -V` orders `26.10` after `26.9` correctly. The `$GITHUB_ENV` line takes effect from the next step on.

---

## 2. Homebrew and XcodeGen

- Homebrew **6.0.22** is preinstalled on macos-26 [2]. **XcodeGen is not preinstalled**: it is absent from the readme's list of tools [2].
- Current XcodeGen: **2.46.0**. Homebrew formula `xcodegen.rb` has `url .../archive/refs/tags/2.46.0.tar.gz` and a bottle for `arm64_tahoe` (macOS 26) [4]. The upstream CHANGELOG has a "Next Version" section above 2.46.0 that is not yet released. It adds `xcode26_3` projectFormat [5]. **(verified)**
- Install. The bottle is sha256-checked by Homebrew itself, and auto-update is off for speed and determinism:
```yaml
- name: Install XcodeGen
  env:
    HOMEBREW_NO_AUTO_UPDATE: "1"
    HOMEBREW_NO_INSTALL_CLEANUP: "1"
    HOMEBREW_NO_ANALYTICS: "1"
    HOMEBREW_NO_ENV_HINTS: "1"
  run: |
    brew install xcodegen
    xcodegen --version            # prints "Version: 2.46.0"
    v=$(xcodegen --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    case "$v" in 2.4[6-9].*|2.[5-9][0-9].*) ;; *) echo "::error::unexpected xcodegen $v"; exit 1;; esac
```
  - `HOMEBREW_NO_AUTO_UPDATE=1` installs the formula version from the brew taps baked into the image. That is 2.46.0 today. The version check guards against a surprise downgrade or upgrade.
  - An alternative matches `docs/ios/inventory.md` §9.5 ("pinned version + SHA-256"). Download `https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip` and check its `shasum -a 256` against a pinned value. github.com/releases is blocked from this container, so I could not obtain the hash. Get it on the first run (TOFU) by printing `shasum -a 256 xcodegen.zip`, then pin it. The brew route already has checksum verification through the bottle sha256 in the formula [4], so I recommend brew for stage 3.
- In `project.yml`, leave `options.projectFormat` unset (the default) or use `xcode16_0`. `xcode26_3` exists only in the unreleased version [5].

---

## 3. ubuntu-latest / Swift on Linux

- **ubuntu-24.04** (image 20260927–20261004): **Swift 6.4** is preinstalled **(verified [7])**. It is installed at `/usr/share/swift/usr/bin`, with symlinks `/usr/local/bin/swift` and `/usr/local/bin/swiftc`. The env var `SWIFT_PATH=/usr/share/swift/usr/bin` is set [8].
- **Important:** "`ubuntu-latest` label will use Ubuntu 26.04 in November 2026" [7]. The current Ubuntu 26.04 readme (image 20260927) **does not list Swift**, although `install-swift.sh` was added to the 26.04 template [9]. **Pin `runs-on: ubuntu-24.04`** and add a guard step: `command -v swift || { echo "::error::no swift"; exit 1; }; swift --version`.
- Plan B if Swift disappears: `container: swift:6.2-noble` (Docker Hub, official image), or install via `swift-actions/setup-swift` (pin the version and SHA).
- `swift test` for a Foundation-only package works. Caveats:
  - `URLSession` / `URLRequest` / `HTTPURLResponse` on Linux live in **FoundationNetworking**. In every file that uses them:
    ```swift
    import Foundation
    #if canImport(FoundationNetworking)
    import FoundationNetworking
    #endif
    ```
  - Linux has **no** Security (Keychain), LocalAuthentication, CryptoKit, Combine, os.log, SwiftUI or UIKit. Keep them out of RouterCore, or wrap them in `#if canImport(...)`. Use `Logger` only on the iOS side.
  - The Swift versions differ: Linux has 6.4, and Xcode 26.x ships Swift 6.2–6.3. Do not use language features newer than Swift 6.2. Use `// swift-tools-version:5.10` or `6.0`. With 6.0, Swift 6 language mode makes strict concurrency an error, so `Sendable` for models and `@MainActor` must be correct. The conservative choice is `5.10`, or 6.0 with `swiftLanguageModes: [.v5]`.
  - Since Swift 6, Foundation on Linux is swift-foundation. JSONDecoder, ISO8601DateFormatter and Date match Apple. Locale-dependent formatting (`DateFormatter` without `locale`) can still differ, so always set `Locale(identifier: "en_US_POSIX")` and `TimeZone` explicitly in tests.
  - XCTest is available on Linux. Swift Testing (`import Testing`) is also in the 6.x toolchain, but XCTest is more conservative.
  - Cost: Linux $0.006/min against macOS $0.062/min [6], so tests on Linux are about 10× cheaper.

---

## 4. Signing for TestFlight without certificates in the repo or secrets

### What the flags do
- `-allowProvisioningUpdates`: for **automatically** signed targets, xcodebuild is allowed to create or update **profiles, App IDs and certificates**. For manual signing it only downloads profiles (man page, quoted in [10]).
- `-authenticationKeyPath <p8> -authenticationKeyID <KEY_ID> -authenticationKeyIssuerID <ISSUER_ID>` use an App Store Connect API key instead of an Apple ID (since Xcode 13). They are needed **for both** `archive` and `-exportArchive`.

### Key role
- **Admin** (Team key). Cloud-managed distribution certificates and automatic creation of App IDs and profiles work with an Admin key **(reports [11])**. The thread author used an Admin key, and iOS App Store export worked: *"an Apple Distribution (Managed) certificate appears in my account"*. A known Apple bug blocks only **Developer ID** cloud signing with an API key, and that does not concern us.
- **App Manager**: no confirmation found. Cloud-managed certificates require the permission "Access to Cloud Managed Distribution Certificate". For people it is enabled in Users and Access [12]. For a key it cannot be enabled separately. The error otherwise is *"You haven't been given access to cloud-managed distribution certificates"* [11]. **Use an Admin key.** Admin is also needed to register a new Bundle ID automatically.

### Does `archive` with automatic signing work on a clean runner?
- Yes, but **every run creates a new "Apple Development" certificate** ("Created via API") whose private key dies with the runner. The certificates pile up until "maximum number of certificates" **(reports [10][13][14])**. I did not find the exact limit in official Apple sources.
- For us this is acceptable: builds are rare (manually, plus once every 2 months). Once in a while the owner can revoke old "Created via API" **Development** certificates in developer.apple.com → Certificates. This **does not affect** builds already in TestFlight, which are signed by the cloud Distribution certificate.
- To avoid creating Development certificates, use an ad-hoc signed archive, as Xcode Cloud does. A forum report says this works [15]:
  `CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=$TEAM`
  Entitlements are kept in the archive, and the real signing happens in `-exportArchive` with the cloud certificate.

### Recommended sequence (variant A, matches `docs/ios/inventory.md` §9.5)
```yaml
- name: Write ASC key
  env:
    ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  run: |
    set -eu
    umask 077
    mkdir -p "$RUNNER_TEMP/asc"
    printf '%s\n' "$ASC_KEY_P8" > "$RUNNER_TEMP/asc/AuthKey_${ASC_KEY_ID}.p8"
    chmod 600 "$RUNNER_TEMP/asc/AuthKey_${ASC_KEY_ID}.p8"
    echo "ASC_KEY_PATH=$RUNNER_TEMP/asc/AuthKey_${ASC_KEY_ID}.p8" >> "$GITHUB_ENV"

- name: Archive
  env:
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    set -eo pipefail
    xcodebuild archive \
      -project ios/Router.xcodeproj -scheme Router -configuration Release \
      -destination 'generic/platform=iOS' \
      -archivePath "$RUNNER_TEMP/Router.xcarchive" \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" \
      | tee "$RUNNER_TEMP/archive.log"
      # (variant B: add CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES)

- name: Export and upload to App Store Connect
  env:
    ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
    ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
    TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  run: |
    set -eo pipefail
    sed "s/__TEAM_ID__/$TEAM_ID/" ios/ExportOptions.plist > "$RUNNER_TEMP/ExportOptions.plist"
    xcodebuild -exportArchive \
      -archivePath "$RUNNER_TEMP/Router.xcarchive" \
      -exportOptionsPlist "$RUNNER_TEMP/ExportOptions.plist" \
      -exportPath "$RUNNER_TEMP/export" \
      -allowProvisioningUpdates \
      -authenticationKeyPath "$ASC_KEY_PATH" \
      -authenticationKeyID "$ASC_KEY_ID" \
      -authenticationKeyIssuerID "$ASC_ISSUER_ID"

- name: Remove ASC key
  if: always()
  run: rm -rf "$RUNNER_TEMP/asc"
```
- Do not use `-quiet` on the first runs, because signing errors are only visible in the full log. Do not use `xcpretty`: it is not installed and it hides lines.
- Never `cat` the .p8 or `set -x` around it. GitHub masks secrets in the log, but a multi-line PEM is masked line by line, which is less reliable.
- If `teamID` cannot be put into the plist via sed, use `/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID"`.

### ExportOptions.plist (in the repo, without secrets; teamID is substituted at build time)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>                         <string>app-store-connect</string>
  <key>destination</key>                    <string>upload</string>
  <key>signingStyle</key>                   <string>automatic</string>
  <key>teamID</key>                         <string>__TEAM_ID__</string>
  <key>uploadSymbols</key>                  <true/>
  <key>manageAppVersionAndBuildNumber</key> <false/>
  <key>testFlightInternalTestingOnly</key>  <true/>
</dict>
</plist>
```
- `method=app-store-connect` replaced `app-store` (Xcode 15.3+), and the old value is deprecated.
- `manageAppVersionAndBuildNumber=false`. The default is YES for App Store, and then Xcode changes the build number itself. We set `CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`.
- `testFlightInternalTestingOnly=true` (Xcode 15+) makes the build internal-only: no external beta and no App Review. This is optional and convenient for us.
- In the `.plist`, write the keys without the alignment spaces above (they were added only for readability). XML ignores whitespace between tags anyway.

### Fallbacks if archive signing fails
1. **Variant B** (ad-hoc archive, see above): fewer certificates, signing only at export [15].
2. **`CODE_SIGNING_ALLOWED=NO` archive → export.** Export re-signs and uploads. **But** reports say the entitlements from the unsigned archive can be lost, and capabilities such as Sign in with Apple stop working [15][16]. Our app has **no capabilities**: Keychain without access groups, and Face ID needs only `NSFaceIDUsageDescription`. So the risk is lower, but still verify. To do that, run an export with `destination=export` first and check `codesign -d --entitlements :- Payload/Router.app` in the .ipa. It should show `application-identifier`, `com.apple.developer.team-identifier`, `get-task-allow=false` and `beta-reports-active=true`. **Last resort.**
3. **Manual signing** (`.p12` plus profile in secrets) is ruled out by the owner's terms. Mention it only as the "if Apple breaks cloud signing" fallback.
- Typical errors:
  - `No profiles for 'xxx' were found` means `-allowProvisioningUpdates` or the key is missing from the command, or the key is not Admin.
  - `Cloud signing permission error` means the key role, or cloud-managed certificates are disabled [11][12].
  - `errSecInternalComponent` from codesign means the runner's login keychain is locked. Create and unlock a temporary keychain (`security create-keychain -p "" ...; security unlock-keychain`).
  - `No suitable application records were found` at upload means **there is no app record in App Store Connect**. It is created by hand: My Apps → + → New App, with the Bundle ID. The API cannot create it.

---

## 5. Upload requirements for App Store Connect (2026)

- **Since 28.04.2026**, iOS/iPadOS apps must be built with the **iOS 26 SDK or later**, so **Xcode 26+**. Older builds are rejected at upload. The deployment target (iOS 17) is not constrained by this **(reports [17], quoting Apple Developer News)**. Expect the next step (iOS 27 SDK / Xcode 27) around spring 2027. The macOS 27 + Xcode 27 image is already in preview [3].
- **Icon:**
  - In an asset catalog (`Assets.xcassets/AppIcon.appiconset`), use a **single-size 1024×1024 PNG**, `"idiom":"universal","platform":"ios","size":"1024x1024"`. It must have **no alpha channel** and no transparency. Otherwise you get **ITMS-90717 "Invalid large app icon... can't be transparent or contain an alpha channel"** [18].
  - Check with `sips -g hasAlpha icon.png`, which must print `hasAlpha: no`. Generating a PNG without alpha: RGB 8-bit (PNG colour type 2).
  - Do not use Icon Composer `.icon`. It had alpha bugs in Xcode 26 [18], and a plain PNG in xcassets works.
- **CFBundleIconName:** with the build setting `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` and the xcassets in the target's resources, actool adds `CFBundleIcons` / `CFBundleIconName` to the built Info.plist itself. Without it the upload fails with ITMS-90713 "Missing Info.plist value CFBundleIconName" (from memory, not confirmed by search). For safety, also put `CFBundleIconName = AppIcon` into Info.plist explicitly.
- **Launch screen is required**, or the upload is rejected (all apps since 2020 must have a launch storyboard or `UILaunchScreen`). With XcodeGen and a manual Info.plist, add `UILaunchScreen` = an empty dict `{}`. It is supported since iOS 14 and fine for iOS 17+.
- **ITSAppUsesNonExemptEncryption = NO** (only HTTPS/system crypto). This is not an upload error, but without it TestFlight holds the build as "Missing Compliance" until someone answers by hand.
- **iPhone only:** `TARGETED_DEVICE_FAMILY = 1`. If iPad is included, either all four orientations or `UIRequiresFullScreen` are needed, otherwise you get ITMS-90474.
- **Build numbers:** `CFBundleVersion` must be unique and increasing within one `CFBundleShortVersionString`. Use `$GITHUB_RUN_NUMBER`. A re-run of the same run gives the same number, and the upload fails with "bundle version already used". In that case run the workflow anew.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` is needed if the app uses "required reason" APIs. **UserDefaults** is category `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`. Without it you get the email/warning **ITMS-91053** [19]. Because we store settings in UserDefaults, add the manifest with `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, empty `NSPrivacyCollectedDataTypes`, and the one UserDefaults/CA92.1 entry. If you add file-timestamp APIs (`attributesOfItem`, `creationDate`), that is a separate category (C617.1).
- **NSFaceIDUsageDescription** is required. It is not an upload error, but without it the app crashes on the first Face ID call.
- Other rules:
  - `CFBundleShortVersionString` must look like `1.0` or `1.0.0`.
  - The Bundle ID in the build must equal the app record in ASC.
  - `CFBundleDisplayName` may be in Cyrillic ("Роутер").
  - Architecture is arm64 only. That is the Xcode 26 default, so set nothing.

---

## 6. GitHub billing (private repo) **(verified [6])**
- Free plan: **2,000 minutes/month**, 500 MB artifacts, 10 GB cache.
- Rates:
  - Linux 2-core: **$0.006/min**
  - Windows: $0.010
  - **macOS 3/4-core (M1): $0.062/min**, about **10.3×** Linux
- The separate "minute multipliers" page now redirects to "Actions runner pricing" (`redirect_from: /billing/reference/actions-minute-multipliers`). The dashboard shows usage as $ ("spend"). In practice the old ×10 holds: 2,000 included minutes ≈ **~190–200 macOS minutes**, or about 3–8 iOS builds of 25–60 minutes.
- Minutes are rounded **up to a whole minute per job** [6].
- Without a payment method, usage stops when the quota runs out. Larger runners (`-large`/`-xlarge`/`-intel` on macOS 26) are billed even within the quota [1][6].
- **A skipped job** (`jobs.<id>.if: false`) never gets a runner, so it uses **0 minutes**. Billing counts only runner processing time [6]. It shows as "skipped" (not as a failure). Put the cheap check, and `if:` on job/steps, on `ubuntu-24.04`. Run the expensive macOS job only via `needs:` + `if:`.

---

## 7. Pitfalls in triggers and secrets **(verified [20][21])**
- **workflow_dispatch:** the "Run workflow" button appears only **if the workflow file exists on the default branch**. After the first run, it can be dispatched via API/CLI against any branch or tag [20]. Conclusion: `ios-testflight.yml` must reach `main` before the first manual run.
- **schedule:** *"Scheduled workflows will only run on the default branch"* [20]. The 2-month cron works only from `main`. GitHub also disables schedule after **60 days without activity in a public repo**. Ours is private, so this does not apply.
- **push** runs on any branch where the workflow file exists in the pushed commit, unless you restrict `branches:` / `paths:`. Recommendation: `on: push: branches: [main] paths: ['ios/**', '.github/workflows/ios-*.yml']` for tests, and for the TestFlight build no push at all, or only `workflow_dispatch` + `schedule`.
- **Secrets in `if:`:** *"Secrets cannot be directly referenced in `if:` conditionals. Instead, consider setting secrets as job-level environment variables..."* [21]. Pattern:
  ```yaml
  jobs:
    preflight:
      runs-on: ubuntu-24.04
      outputs:
        ok: ${{ steps.chk.outputs.ok }}
      steps:
        - id: chk
          env:
            K1: ${{ secrets.ASC_KEY_P8 }}
            K2: ${{ secrets.ASC_KEY_ID }}
            K3: ${{ secrets.ASC_ISSUER_ID }}
            K4: ${{ secrets.APPLE_TEAM_ID }}
          run: |
            ok=true
            for n in K1 K2 K3 K4; do eval "v=\${$n:-}"; [ -n "$v" ] || { echo "::warning::secret $n missing"; ok=false; }; done
            echo "ok=$ok" >> "$GITHUB_OUTPUT"
    build:
      needs: preflight
      if: needs.preflight.outputs.ok == 'true'
      runs-on: macos-26
  ```
  The check runs on cheap Linux. Without the secrets, the macOS job is skipped and uses 0 minutes.
- Also set:
  - `permissions: contents: read`
  - `concurrency: { group: ios-testflight, cancel-in-progress: false }`
  - `timeout-minutes: 40` on the macOS job
  - `actions/checkout` pinned to a SHA (or at least `@v4`/`@v5`), with `persist-credentials: false`.

---

## Sources
1. runner-images README (labels, -latest policy, Xcode policy): https://raw.githubusercontent.com/actions/runner-images/main/README.md
2. macOS 26 arm64 image readme: https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-arm64-Readme.md · 2b. macOS 15 arm64: .../images/macos/macos-15-arm64-Readme.md
3. Xcode 27 preview image readme: .../images/macos/xcode-27-arm64-Readme.md
4. Homebrew formula xcodegen: https://raw.githubusercontent.com/Homebrew/homebrew-core/main/Formula/x/xcodegen.rb
5. XcodeGen CHANGELOG: https://raw.githubusercontent.com/yonaskolb/XcodeGen/master/CHANGELOG.md
6. GitHub docs, billing: github/docs `content/billing/concepts/product-billing/github-actions.md`, `content/billing/reference/actions-runner-pricing.md`, `data/reusables/billing/actions-standard-runner-prices.md`, `actions-included-quotas.md` (raw.githubusercontent.com/github/docs/main/...)
7. Ubuntu 24.04 image readme: .../images/ubuntu/Ubuntu2404-Readme.md (Swift 6.4; announcement about ubuntu-latest → 26.04 in November 2026); Ubuntu 26.04: .../images/ubuntu/Ubuntu2604-Readme.md
8. install-swift.sh: .../images/ubuntu/scripts/build/install-swift.sh
9. build.ubuntu-26_04.pkr.hcl: .../images/ubuntu/templates/build.ubuntu-26_04.pkr.hcl
10. Apple forums: https://developer.apple.com/forums/thread/695759 (private key not installed), https://developer.apple.com/forums/thread/764554
11. Apple forums: https://developer.apple.com/forums/thread/776036 (Admin API key; Developer ID bug; iOS App Store cloud signing works)
12. Apple forums: https://developer.apple.com/forums/thread/772909 and the search result about "Access to Cloud Managed Distribution Certificate"
13. Bitrise: https://discuss.bitrise.io/t/new-development-certificates-created-with-every-build/21068
14. Blog (Aug 2026, GitHub Actions cloud signing pitfalls): https://rxliuli.com/blog/two-pitfalls-of-safari-cloud-signing-in-github-actions (the blog did not open for me; known only from the search snippet)
15. Apple forums: https://developer.apple.com/forums/thread/756119 (ad-hoc archive `CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES`)
16. https://zenn.dev/colomney/scraps/c6a503fad4da72 (entitlements lost with unsigned archive)
17. https://expo.dev/blog/app-store-connect-minimum-sdk-26, https://capgo.app/blog/xcode-26-requirement-for-capacitor-apps/ (iOS 26 SDK since 28.04.2026)
18. Apple forums: https://developer.apple.com/forums/thread/798597, https://developer.apple.com/forums/thread/795411 (ITMS-90717 on Xcode 26)
19. Apple forums: https://developer.apple.com/forums/thread/750341 (ITMS-91053, UserDefaults CA92.1)
20. GitHub docs, events-that-trigger-workflows.md (workflow_dispatch / schedule on default branch)
21. GitHub docs, workflow-syntax.md and use-secrets.md ("Secrets cannot be directly referenced in `if:`")
