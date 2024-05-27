#!/bin/bash

rm -rf MiddleMouseFocus.app && \
mkdir -p MiddleMouseFocus.app/Contents/MacOS && \
mkdir MiddleMouseFocus.app/Contents/Resources && \
cp MiddleMouseFocus MiddleMouseFocus.app/Contents/MacOS && \
cp Info.plist MiddleMouseFocus.app/Contents && \
cp MiddleMouseFocus.icns MiddleMouseFocus.app/Contents/Resources && \
chmod 755 MiddleMouseFocus.app && echo "Successfully created MiddleMouseFocus.app"
