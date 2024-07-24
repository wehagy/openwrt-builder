#!/usr/bin/env bash

set -eux

download_file() {
    local repo="${1}"
    local tag="${2}"
    local repo_name="${repo##*/}"
    curl -sL "https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz" -o "${repo_name}-${tag:1}.tar.gz"
}

calculate_sha256() {
    local file="${1}"
    sha256sum "${file}" | cut --delimiter=' ' --fields=1
    rm "${file}"
}

REPO="netbirdio/netbird"
# Get the latest tag from the remote repository
REMOTE_TAG="$(
    git ls-remote \
        --refs \
        --tags \
        --sort='-version:refname' \
        "https://github.com/${REPO}.git" \
    | head --lines=1 \
    | cut --delimiter='/' --fields=3
)"
REMOTE_TAG_STRIP="${REMOTE_TAG:1}"
# Get the local version from the Makefile
quilt push -a
LOCAL_TAG="$(grep -oP '(?<=PKG_VERSION:=).+' custom-feed/netbird/Makefile)"
LOCAL_TAG_STRIP="${LOCAL_TAG}"

# Check if the remote version is newer than the local version
if [[ "$(printf '%s\n%s' "${REMOTE_TAG_STRIP}" "${LOCAL_TAG_STRIP}" | sort --version-sort --check=quiet ; echo "${?}")" == 0 ]]; then
    printf '%s\n' "Exiting script: No update needed."
else
    printf '%s\n' "Updating: Newer version found."
    download_file "$REPO" "$REMOTE_TAG"
    SHA256=$(calculate_sha256 "${REPO##*/}-${REMOTE_TAG_STRIP}.tar.gz")
    # Update the Makefile with the SHA256 hash and the remote version
    quilt new netbird-200-update_to_"${REMOTE_TAG_STRIP}".patch
    quilt add custom-feed/netbird/Makefile
    sed -i "s/PKG_HASH:=.*/PKG_HASH:=${SHA256}/" custom-feed/netbird/Makefile
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${REMOTE_TAG_STRIP}/" custom-feed/netbird/Makefile
    quilt refresh

    # Add the SHA256 hash to the output if in a GitHub Actions environment
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "sha256=${SHA256}" >> "${GITHUB_OUTPUT:-}"
fi

quilt pop -a

exit 0
