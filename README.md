name: Build NEXO Android APK

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Extract project
        run: |
          unzip -o nexo_ai_video_maker_phone_build.zip -d source

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.0'
          channel: stable

      - name: Create Android project
        run: flutter create --platforms=android --project-name nexo_ai_video_maker build_app

      - name: Copy NEXO source
        run: |
          cp source/flutter/pubspec.yaml build_app/pubspec.yaml
          rm -rf build_app/lib
          cp -R source/flutter/lib build_app/lib

      - name: Install packages
        working-directory: build_app
        run: flutter pub get

      - name: Build APK
        working-directory: build_app
        run: flutter build apk --release

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: nexo-release-apk
          path: build_app/build/app/outputs/flutter-apk/app-release.apk
