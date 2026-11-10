#!/bin/sh
#
# Script buid building and packaging the Hyperloop iOS package
#
CWD=`pwd`
CURVERSION=`grep "^version:" manifest`
VERSION=`grep "^version:" manifest | cut -c 10-`
METABASE_VERSION=`grep "\"version\":" ../packages/hyperloop-ios-metabase/package.json | cut -d \" -f 4`
export TITANIUM_SDK="13.2.0.GA"

echo "Titanium SDK version: "
echo $TITANIUM_SDK

CHECK="✓ "

rm -rf build

# Inject the TITANIUM_SDK value into titanium.xcconfig explicitly, just exporting the value doesn't override it, it seems
sed -i.bak 's@TITANIUM_SDK = .*@TITANIUM_SDK = '"$TITANIUM_SDK"'@g' ./titanium.xcconfig

if [ "${CI}" = "1" ];
then
	echo "Testing ..."
	xcodebuild clean >/dev/null
	./test.sh || exit $?
fi

# Build the native module
echo "\nBuilding module ..."
mkdir -p build/zip
ti build -p ios --build-only || exit $?
cd dist || exit $?
unzip hyperloop-iphone-$VERSION.zip -d ../build/zip || exit $?
cd .. || exit $?

# Package the metabase into the .zip
echo "Packaging iOS metabase..."
cd ../packages/hyperloop-ios-metabase || exit $?
rm -f *.tgz
npm pack >/dev/null 2>&1 || exit $?
cd "$CWD" || exit $?

# Install dependencies
echo "Installing npm dependencies..."
cd build/zip/modules/iphone/hyperloop/$VERSION/hooks || exit $?
npm i --production || exit $?
npm i "$CWD"/../packages/hyperloop-ios-metabase/hyperloop-metabase-$METABASE_VERSION.tgz || exit $?
rm -rf node_modules/findit/test
rm -rf package-lock.json
cd "$CWD" || exit $?

cd "$CWD"/build/zip || exit $?
rm -rf "$CWD"/hyperloop-iphone-$VERSION.zip
zip -q -r "$CWD"/hyperloop-iphone-$VERSION.zip * --exclude=*test* --exclude=*.DS_Store* --exclude=*.git* --exclude *.travis.yml*  --exclude *.gitignore*  --exclude *.npmignore* --exclude *CHANGELOG* --exclude *.jshintrc* || exit $?

unset TITANIUM_SDK

echo "$CHECK Done packaging iOS module!\n"
exit 0
