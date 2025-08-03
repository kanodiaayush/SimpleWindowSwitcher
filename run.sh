#!/bin/bash

echo "Building SimpleWindowSwitcher (release)..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "Stripping debug symbols..."
    strip .build/release/SimpleWindowSwitcher
    
    echo ""
    echo "SimpleWindowSwitcher built successfully!"
    echo "Executable size: $(ls -lh .build/release/SimpleWindowSwitcher | awk '{print $5}')"
    echo ""
    echo "Starting SimpleWindowSwitcher..."
    echo "Press Ctrl+C to quit"
    echo ""
    .build/release/SimpleWindowSwitcher
else
    echo "Build failed!"
    exit 1
fi 