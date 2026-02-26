.PHONY: build test clean notarize setup-config

build:
	sh scripts/build-dmg.sh

test:
	swift test --package-path Packages/LockOutCore

clean:
	rm -rf build/ dist/

notarize:
	xcrun notarytool submit dist/LockOut.dmg --keychain-profile AC_PASSWORD --wait

setup-config:
	@if [ ! -f Config.xcconfig ]; then cp Config.xcconfig.template Config.xcconfig; echo "Created Config.xcconfig from template."; else echo "Config.xcconfig already exists, skipping."; fi
