# PixDrop

GitHub Actions automatically builds the Android release APK.

## Upload
Upload the contents of this folder to the ROOT of your GitHub repository.
The repository should contain:
- lib/main.dart
- pubspec.yaml
- .github/workflows/build-apk.yml

## APK
After uploading/committing to the `main` branch:
1. Open GitHub -> Actions
2. Open `Build PixDrop APK`
3. Open the latest successful run
4. Download artifact `pixdrop-release-apk`
5. Inside it is `app-release.apk`
