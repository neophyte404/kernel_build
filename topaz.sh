#!/usr/bin/env bash

set -ex

WORK_DIR=$(pwd)

ANYKERNEL="${WORK_DIR}/anykernel"
KERNEL_DIR="topaz"

DATE=$(date +"%Y%m%d-%H%M")
START=$(date +"%s")

export ARCH=arm64
export KBUILD_BUILD_HOST="neokun"
export KBUILD_BUILD_USER="neo-server"

DEVICE="Xiaomi Redmi Note 12"
CODENAME="topaz"

DEFCONFIG="gki_defconfig"

PROCS=$(nproc --all)

export USE_CCACHE=1

ccache -M 100G

LC_ALL=C
export LC_ALL

# Telegram message
tg() {
    curl -sX POST \
    "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="${chat_id}" \
    -d parse_mode=Markdown \
    -d disable_web_page_preview=true \
    -d text="$1"
}

# Telegram file upload
tgs() {
    MD5=$(md5sum "$1" | cut -d' ' -f1)

    curl -fsSL -X POST \
    "https://api.telegram.org/bot${token}/sendDocument" \
    -F document=@"$1" \
    -F chat_id="${chat_id}" \
    -F parse_mode=Markdown \
    -F caption="$2 | *MD5*: \`${MD5}\`"
}

# Build info
sendinfo() {
    tg "
*Destruction Kernel CI*

*Device:* \`${DEVICE} (${CODENAME})\`
*Branch:* \`${BRANCH}\`
*Date:* \`${DATE}\`
*Compiler Host:* \`$KBUILD_BUILD_HOST\`
"
}

# Sync source
sync_source() {

    cd "$WORK_DIR"

    echo "Syncing manifest"
    repo init -u https://github.com/neophyte404/kernel_manifest.git -b main
    repo sync
    sudo apt install -y ccache
    echo "Done"
}

# Compile kernel
compile() {

    cd "${KERNEL_DIR}"

    if [ -d out ]; then
        rm -rf out
    fi

    mkdir -p out

    LTO=thin \
    BUILD_CONFIG=build.config.gki.aarch64 \
    build/build.sh

    IMAGE="${KERNEL_DIR}/out/android13-5.15/dist/Image"

    if ! [ -f "${IMAGE}" ]; then
        tg "*Build failed!*"
        exit 1
    fi

    cd "$WORK_DIR"

    git clone --depth=1 \
    https://github.com/neophyte404/Anykernel3.git \
    "${ANYKERNEL}" \
    -b topaz

    cp "${IMAGE}" "${ANYKERNEL}/Image"
}

# Make zip
zipping() {

    cd "${ANYKERNEL}"

    ZIPNAME="Destruction-${CODENAME}-${DATE}.zip"

    zip -r9 "${ZIPNAME}" ./*
}

# Upload zip
push_zip() {

    cd "${ANYKERNEL}"

    ZIP=$(ls *.zip)

    END=$(date +"%s")
    DIFF=$((END - START))

    tgs "${ZIP}" \
    "Build took $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)"
}

# Main
sendinfo
sync_source
compile
zipping
push_zip
