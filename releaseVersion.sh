#!/bin/bash
set -e

if [ "$#" -ne 1 ]; then
	echo >&2 "Illegal number of parameters"
	echo >&2 "releaseVersion.sh <version>"
	exit -1
fi

if [[ -n $(git status --porcelain) ]]; then
	echo >&2 "Cannot release version because there are unstaged changes:"
	git status --short
	exit -2
fi

if [[ -n $(git tag --contains $(git rev-parse --verify HEAD)) ]]; then
	echo >&2 "The latest commit is already contained in the following releases:"
	git tag --contains $(git rev-parse --verify HEAD)
	exit -3
fi

if [[ -n $(git log --branches --not --remotes) ]]; then
	echo "Pushing commits to git"
	git push
fi

echo "Creating release notes"

RELEASE_NOTES_FILE=._tmp_release_notes.md

touch "${RELEASE_NOTES_FILE}"
open -Wn "${RELEASE_NOTES_FILE}"

if ! [ -s "${RELEASE_NOTES_FILE}" ]; then
	echo -e >&2 "\033[1;31mNo release notes provided, aborting.\033[0m"
	rm -f "${RELEASE_NOTES_FILE}"
	exit -1
fi

echo "Creating commit for version"

VERSION="$1"

echo "\"$VERSION\"" > applesimutils/applesimutils/version.h

echo "Cleaning up"

git clean -xdf

echo "Creating a compressed tarball of the source"

SRC_TGZ_FILE="AppleSimulatorUtils-${VERSION}.tar.gz"

mkdir -p build
tar --exclude="releaseVersion.sh" --exclude=".git" --exclude="build" --exclude="bottle" --exclude "._tmp_release_notes.md" --exclude=".github" --exclude="homebrew-brew" -cvzf "build/${SRC_TGZ_FILE}" .

echo "Creating a homebrew bottle"

BOTTLE_TGZ_FILE="applesimutils-${VERSION}.mojave.bottle.tar.gz"

rm -fr bottle
BOTTLE_DIR="bottle/applesimutils/${VERSION}/"
mkdir -p "${BOTTLE_DIR}"
./buildForBrew.sh "${BOTTLE_DIR}"
pushd .
cd bottle
tar -cvzf "${BOTTLE_TGZ_FILE}" applesimutils
popd

echo "Updating brew repository with latest tarball and update applesimutils.rb"

pushd .
cd homebrew-brew

git checkout master
git fetch
git pull --rebase
sed -i '' -e 's/^\ \ url .*/\ \ url '"'https:\/\/github.com\/wix\/AppleSimulatorUtils\/releases\/download\/${VERSION}\/${SRC_TGZ_FILE}'"'/g' applesimutils.rb
sed -i '' -e 's/^\ \ \ \ root\_url .*/\ \ \ \ root\_url '"'https:\/\/github.com\/wix\/AppleSimulatorUtils\/releases\/download\/${VERSION}'"'/g' applesimutils.rb
sed -i '' -e 's/^\ \ sha256 .*/\ \ sha256 '"'"$(shasum -b -a 256 ../build/${SRC_TGZ_FILE} | awk '{ print $1 }')"'"'/g' applesimutils.rb
sed -i '' -e 's/^\ \ \ \ sha256 .*/\ \ \ \ sha256 '"'"$(shasum -b -a 256 ../bottle/${BOTTLE_TGZ_FILE} | awk '{ print $1 }')"'"'\ \=\>\ \:mojave/g' applesimutils.rb
git add -A
git commit -m "$1"
git push

popd

echo "Pushing changes to AppleSimUtils"

git add -A
git commit -m "$1"
git tag "$1"

git push
git push --tags

echo "Creating a GitHub release"

#Escape user input in markdown to valid JSON string using PHP 🤦‍♂️ (https://stackoverflow.com/a/13466143/983912)
RELEASENOTESCONTENTS=$(printf '%s' "$(<"${RELEASE_NOTES_FILE}")" | php -r 'echo json_encode(file_get_contents("php://stdin"));')
API_JSON=$(printf '{"tag_name": "%s","target_commitish": "master", "name": "%s", "body": %s, "draft": false, "prerelease": false}' "$VERSION" "$VERSION" "$RELEASENOTESCONTENTS")
RELEASE_ID=$(curl -s --data "$API_JSON" https://api.github.com/repos/wix/AppleSimulatorUtils/releases?access_token=${GITHUB_RELEASES_TOKEN} | jq ".id")

echo -e "\033[1;34mUploading attachments to release\033[0m"

curl -s --data-binary @"${SRC_TGZ_FILE}" -H "Content-Type: application/octet-stream" "https://uploads.github.com/repos/wix/AppleSimulatorUtils/releases/${RELEASE_ID}/assets?name=$(basename ${SRC_TGZ_FILE})&access_token=${GITHUB_RELEASES_TOKEN}" | jq "."
curl -s --data-binary @"${BOTTLE_TGZ_FILE}" -H "Content-Type: application/octet-stream" "https://uploads.github.com/repos/wix/AppleSimulatorUtils/releases/${RELEASE_ID}/assets?name=$(basename ${SRC_TGZ_FILE})&access_token=${GITHUB_RELEASES_TOKEN}" | jq "."

# rm -fr build
# rm -fr bottle
# rm -f "${RELEASE_NOTES_FILE}"