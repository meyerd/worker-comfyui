#!/usr/bin/env bash

url="$1"
full_path="$2"

destination_dir=$(dirname "$full_path")
destination_file=$(basename "$full_path")

mkdir -p "$destination_dir"

# Simple corruption check: file < 10MB or .aria2 files
if [ -f "$full_path" ]; then
    size_bytes=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo 0)
    size_mb=$((size_bytes / 1024 / 1024))

    if [ "$size_bytes" -lt 10485760 ]; then  # Less than 10MB
        echo "🗑️  Deleting corrupted file (${size_mb}MB < 10MB): $full_path"
        rm -f "$full_path"
    else
        echo "✅ $destination_file already exists (${size_mb}MB), skipping download."
        return 0
    fi
fi

# Check for and remove .aria2 control files
if [ -f "${full_path}.aria2" ]; then
    echo "🗑️  Deleting .aria2 control file: ${full_path}.aria2"
    rm -f "${full_path}.aria2"
    rm -f "$full_path"  # Also remove any partial file
fi

echo "📥 Downloading $destination_file to $destination_dir..."

# Download without falloc (since it's not supported in your environment)
aria2c -x 16 -s 16 -k 1M --continue=true -d "$destination_dir" -o "$destination_file" "$url"