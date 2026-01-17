#!/bin/bash

# Ensure we are in the directory of the script
cd "$(dirname "$0")"
SCRIPT_DIR="$(pwd)"

# Configuration
# Resolving Absolute Path to Repo Root (Parent of script dir)
PROJECT_DIR="$(cd .. && pwd)"
PROJECT_FILE="$PROJECT_DIR/Resolver.xcodeproj/project.pbxproj"
BUILD_OUTPUT_DIR="$PROJECT_DIR/Build"
DERIVED_DATA_DIR="$BUILD_OUTPUT_DIR/build_xcode"

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

# 5. Create Styled DMG
echo "Creating Styled DMG..."

# Paths
DMG_STAGING="$BUILD_OUTPUT_DIR/dmg_staging"
DMG_TMP="$BUILD_OUTPUT_DIR/Resolver_rw.dmg"
DMG_FINAL="$BUILD_OUTPUT_DIR/Resolver.dmg"

# Clean up previous runs
rm -rf "$DMG_STAGING" "$DMG_TMP" "$DMG_FINAL"

# 5.1 Prepare Staging Area
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# 5.2 Create Temporary Read-Write DMG
hdiutil create -volname "Resolver" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_TMP"

# 5.3 Mount the DMG
DEVICE=$(hdiutil attach -readwrite -noverify "$DMG_TMP" | egrep '^/dev/' | sed 1q | awk '{print $1}')
sleep 2

# 5.4 Apply Styling with AppleScript
echo "Applying styling..."
osascript <<EOF
tell application "Finder"
    tell disk "Resolver"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 800, 400}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        make new alias file at container window to file "Applications" with properties {name:"Applications"}
        set position of item "Resolver" of container window to {120, 150}
        set position of item "Applications" of container window to {280, 150}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# 5.5 Unmount and Convert to Read-Only
echo "Finalizing DMG..."
chmod -Rf go-w /Volumes/Resolver
sync
hdiutil detach "$DEVICE"
sleep 2

echo "Converting to compressed DMG..."
hdiutil convert "$DMG_TMP" -format UDZO -o "$DMG_FINAL"

# Cleanup
rm -rf "$DMG_STAGING" "$DMG_TMP"

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
