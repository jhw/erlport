#!/bin/bash
# Script to update include paths after reorganization to per-language subdirectories

set -e

echo "Updating include directives in language subdirectories..."

# Update erlport.hrl references in language .hrl files
for file in src/python/python.hrl src/ruby/ruby.hrl src/go/go.hrl; do
    if [ -f "$file" ]; then
        echo "  Updating $file"
        sed -i '' 's|-include("erlport.hrl")|-include("../erlport.hrl")|g' "$file"
    fi
done

echo "✓ Include directives updated"
echo ""
echo "All references updated successfully!"
