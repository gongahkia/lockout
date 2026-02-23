.PHONY: build test clean notarize

build:
	sh scripts/build-dmg.sh

test:
	swift test --package-path Packages/LockOutCore

clean:
	rm -rf build/ dist/

notarize:
	xcrun notarytool submit dist/LockOut.dmg --keychain-profile AC_PASSWORD --wait
