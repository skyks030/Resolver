#!/bin/bash

# Configuration
# Path to the .xcodeproj directory relative to this script
# Assuming this script is in Resolver/deploy.sh and project is ../Resolver.xcodeproj
PROJECT_DIR=".."
PROJECT_FILE="$PROJECT_DIR/Resolver.xcodeproj/project.pbxproj"
BUILD_OUTPUT_DIR="$PROJECT_DIR/Build"
DERIVED_DATA_DIR="$PROJECT_DIR/build_xcode"

# Ensure we are in the directory of the script
cd "$(dirname "$0")"

# Check if project file exists
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: Project file not found at $PROJECT_FILE"
    exit 1
fi

# 1. Get Current Version
current_version=$(grep "MARKETING_VERSION" "$PROJECT_FILE" | head -1 | sed -E 's/.*MARKETING_VERSION = (.*);/\1/' | tr -d '[:space:]')
echo "Current Version: $current_version"

# 2. Ask for New Version
read -p "Enter new version number: " new_version

if [ -z "$new_version" ]; then
    echo "No version provided. Exiting."
    exit 1
fi

# 3. Update Version in Xcode Project
echo "Updating version to $new_version in project file..."
sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $new_version;/g" "$PROJECT_FILE"
sed -i '' "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $new_version;/g" "$PROJECT_FILE"

# 4. Build the App
echo "Building Resolver (Release)..."
# Run xcodebuild from the project root. Force Universal Binary (arm64 + x86_64)
(cd "$PROJECT_DIR" && xcodebuild -scheme Resolver -configuration Release -derivedDataPath "$DERIVED_DATA_DIR" ARCHS="arm64 x86_64" clean build)

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/Resolver.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH"
    exit 1
fi

# 5. Create DMG
echo "Creating DMG..."
mkdir -p "$BUILD_OUTPUT_DIR"
DMG_PATH="$BUILD_OUTPUT_DIR/Resolver.dmg"

# Remove old DMG
rm -f "$DMG_PATH"

# Create new DMG using a staging directory to ensure the App itself is inside the DMG, not just its contents
DMG_STAGING="$BUILD_OUTPUT_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"

hdiutil create -volname "Resolver" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

# Cleanup staging
rm -rf "$DMG_STAGING"

if [ $? -ne 0 ]; then
    echo "❌ DMG creation failed."
    exit 1
fi

# 6. Update version.txt
echo "$new_version" > "$BUILD_OUTPUT_DIR/version.txt"

# 7. Git Operations
echo "Committing and pushing to GitHub..."
# Go to project root for git operations
cd "$PROJECT_DIR"

git add Resolver.xcodeproj/project.pbxproj
git add Build/version.txt
git add Build/Resolver.dmg
git commit -m "Release version $new_version"
git push origin main

echo "✅ Deployment complete! Version $new_version is live."
