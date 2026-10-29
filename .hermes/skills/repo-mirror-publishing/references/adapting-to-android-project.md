# Adapting Mirror Scripts to an Android Project

Session reference: migration from `j0nix-os` (NixOS) mirror pipeline to `rydeon-android` (Android).

## Files to adapt

| File | NixOS original | Android replacement |
|---|---|---|
| `.mirror-blacklist` | `.sops.yaml`, `settings.nix`, `profiles/*` | `app/src/play/`, `docs/private/`, `*.jks`, `secrets/`, `keystore/`, `local.properties`, `.drone.yml` |
| `.mirror-root-whitelist` | `flake.lock`, `flake.nix`, `Makefile` | `build.gradle`, `settings.gradle`, `gradlew`, `FLAVORS.md`, `LICENSE` |
| `scripts/lib/mirror-sanitize.sh` | `ms_sensitive_files_list()` returned NixOS paths | Replaced with Android paths |
| `scripts/publish-public-github.sh` | Tree-filter removed `.sops.yaml`, `settings.nix`, `profiles/*` | Removed `app/src/play`, `docs/private`, `*.jks`, `local.properties`, `.drone.yml`, `secrets/`, `keystore/` |
| `scripts/export-public-github.sh` | Removed NixOS secrets, kept `.example` templates | Removed Android proprietary source sets, no `.example` concept needed |
| `scripts/regenerate-readme.py` | Template-based (`templates/README.md.tmpl`) | Template-based with `$source_notice` only; body shared across scopes |

## Bugs caught during adaptation

### 1. Missing `rm` in tree-filter
```bash
# WRONG — bare path is a no-op in shell
docs/private/ 2>/dev/null || true

# CORRECT
rm -rf docs/private/ 2>/dev/null || true
```

### 2. Duplicate `PUBLIC_CUTOFF_COMMIT_FALLBACK` in `.drone.star`
Drone Starlark does not deduplicate dict keys. Declaring the same key twice silently keeps the last value, which may be the wrong one. Remove the duplicate.

### 3. Broken `.gitignore` rules
Leading pipe characters in `.gitignore` entries (`|/.idea`, `|.kotlin/`) are treated as literal filenames, causing IDE files to leak into commits. Strip the pipe prefix.

## Android Play Store build pipeline in same Drone CI

When the private repo also builds the Play Store APK (via a `play` product flavor), add a second Drone pipeline that runs in parallel with the mirror pipeline.

### Gradle signing config (local-dev safe)

In `app/build.gradle`, gate the release signing config behind an env-var check so local builds stay unsigned but CI produces a signed bundle:

```gradle
def hasSigningEnv = System.getenv("ANDROID_KEYSTORE_PASSWORD") != null

signingConfigs {
    if (hasSigningEnv) {
        release {
            storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH") ?: "app/keystore.jks")
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
        }
    }
}

buildTypes {
    release {
        if (hasSigningEnv) {
            signingConfig signingConfigs.release
        }
        minifyEnabled false
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

### Keystore delivery via Drone secrets

Encode the JKS keystore as base64 and store it in a Drone secret:

```bash
base64 -w 0 release-key.jks
# paste output into Drone → repository secrets → android_keystore_base64
```

### CI scripts

`scripts/ci-setup-keystore.sh` — decode base64 keystore:
```bash
keystore_path="${ANDROID_KEYSTORE_PATH:-app/keystore.jks}"
if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
    echo "WARN: no keystore secret; unsigned build." >&2; exit 0
fi
printf '%s\n' "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$keystore_path"
```

`scripts/ci-build-play.sh` — orchestrate build:
```bash
export ANDROID_KEY_PASSWORD="${ANDROID_KEY_PASSWORD:-${ANDROID_KEYSTORE_PASSWORD:-}}"
scripts/ci-setup-keystore.sh
./gradlew :app:bundlePlayRelease
```

### `.drone.star` additions

```python
ANDROID_IMAGE = "cimg/android:2024.12.1-node"

def build_play_pipeline():
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "build-play",
        "trigger": {"branch": ["main"], "event": ["push", "tag"]},
        "steps": [{
            "name": "build-play-release",
            "image": ANDROID_IMAGE,
            "environment": {
                "ANDROID_KEYSTORE_BASE64": {"from_secret": "android_keystore_base64"},
                "ANDROID_KEYSTORE_PASSWORD": {"from_secret": "android_keystore_password"},
                "ANDROID_KEY_ALIAS": {"from_secret": "android_key_alias"},
                "ANDROID_KEY_PASSWORD": {"from_secret": "android_key_password"},
                "ANDROID_KEYSTORE_PATH": "app/keystore.jks",
            },
            "commands": ['scripts/ci-build-play.sh'],
        }],
    }
```

Run `bash -n scripts/*.sh` after authoring to catch syntax errors before the first CI run.


### Gradle Play Publisher (upload to Play Store)

Add the plugin to `app/build.gradle`:

```gradle
plugins {
    id 'com.github.triplet.play' version '3.9.1'
}

def playServiceAccountPath = System.getenv("PLAY_STORE_SERVICE_ACCOUNT_JSON")
if (playServiceAccountPath != null && file(playServiceAccountPath).exists()) {
    play {
        serviceAccountCredentials.set(file(playServiceAccountPath))
        track.set(System.getenv("PLAY_STORE_TRACK") ?: "internal")
    }
}
```

Provide the service account JSON via a Drone secret (base64-encoded):

```bash
base64 -w 0 play-store-service-account.json
# paste into Drone → repository secrets → play_store_service_account_base64
```

In CI, decode the secret and let the build script decide whether to upload:

```bash
# scripts/ci-build-play.sh (excerpt)
if [ -n "${PLAY_STORE_SERVICE_ACCOUNT_BASE64:-}" ]; then
    temp_json="$(mktemp -t play-store-sa-XXXXXX.json)"
    printf '%s\n' "$PLAY_STORE_SERVICE_ACCOUNT_BASE64" | base64 -d > "$temp_json"
    export PLAY_STORE_SERVICE_ACCOUNT_JSON="$temp_json"
fi

if [ -n "${PLAY_STORE_SERVICE_ACCOUNT_JSON:-}" ] && [ -f "$PLAY_STORE_SERVICE_ACCOUNT_JSON" ]; then
    gradle_task="publishBundle"      # build + upload
else
    gradle_task="bundlePlayRelease"  # build only (AAB)
fi
```

### Complete Drone secrets checklist for Android

| Secret | How to generate |
|---|---|
| `android_keystore_base64` | `base64 -w 0 release-key.jks` |
| `android_keystore_password` | Keystore password |
| `android_key_alias` | Alias from `keytool -list -keystore ...` |
| `android_key_password` | Key password (optional, falls back to store password) |
| `play_store_service_account_base64` | `base64 -w 0 service-account.json` (optional) |

---

## Pre-flight checklist

- [ ] `bash -n scripts/*.sh` passes syntax check on all scripts
- [ ] `python3 scripts/regenerate-readme.py --scope public --output /tmp/test.md` works
- [ ] `.mirror-blacklist` and `.mirror-root-whitelist` are created and committed
- [ ] `publish-public-github.sh` tree-filter has no bare paths
- [ ] `.drone.star` has only one `PUBLIC_CUTOFF_COMMIT_FALLBACK` definition
- [ ] `.gitignore` has no leading pipe characters
- [ ] Play Store service account JSON has `Pub/Sub Publisher` role in Google Cloud IAM
- [ ] Service account is added as a user in Google Play Console with `Release Manager` role
