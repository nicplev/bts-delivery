#!/bin/bash

# App Icon Generator Script for iOS
# Usage: ./generate_app_icons.sh <source_image.png>

if [ -z "$1" ]; then
    echo "Usage: ./generate_app_icons.sh <source_image.png>"
    echo "Example: ./generate_app_icons.sh my_icon.png"
    exit 1
fi

SOURCE_IMAGE="$1"
OUTPUT_DIR="ios/Runner/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image '$SOURCE_IMAGE' not found!"
    exit 1
fi

echo "🎨 Generating iOS app icons from: $SOURCE_IMAGE"
echo "📁 Output directory: $OUTPUT_DIR"
echo ""

# Create backup of existing icons
BACKUP_DIR="${OUTPUT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
echo "📦 Creating backup at: $BACKUP_DIR"
cp -r "$OUTPUT_DIR" "$BACKUP_DIR"

# Array of sizes: "filename:width:height"
declare -a SIZES=(
    "Icon-App-20x20@1x.png:20:20"
    "Icon-App-20x20@2x.png:40:40"
    "Icon-App-20x20@3x.png:60:60"
    "Icon-App-29x29@1x.png:29:29"
    "Icon-App-29x29@2x.png:58:58"
    "Icon-App-29x29@3x.png:87:87"
    "Icon-App-40x40@1x.png:40:40"
    "Icon-App-40x40@2x.png:80:80"
    "Icon-App-40x40@3x.png:120:120"
    "Icon-App-60x60@2x.png:120:120"
    "Icon-App-60x60@3x.png:180:180"
    "Icon-App-76x76@1x.png:76:76"
    "Icon-App-76x76@2x.png:152:152"
    "Icon-App-83.5x83.5@2x.png:167:167"
    "Icon-App-1024x1024@1x.png:1024:1024"
)

# Generate each size
for size_info in "${SIZES[@]}"; do
    IFS=':' read -r filename width height <<< "$size_info"
    output_path="${OUTPUT_DIR}/${filename}"

    echo "✨ Generating ${width}x${height} -> ${filename}"

    sips -z $height $width "$SOURCE_IMAGE" --out "$output_path" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "   ✅ Success"
    else
        echo "   ❌ Failed"
    fi
done

echo ""
echo "✨ Icon generation complete!"
echo "📋 Generated $(ls -1 ${OUTPUT_DIR}/*.png | wc -l) icon files"
echo ""
echo "🔄 Next steps:"
echo "   1. Open Xcode and verify the icons look correct"
echo "   2. Build your app: flutter clean && flutter build ios"
echo "   3. If icons don't appear, try: Clean Build Folder in Xcode"
echo ""
echo "💾 Backup saved at: $BACKUP_DIR"
