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

VARIANT="${1:-Vanilla}"
DEFCONFIG="gki_defconfig"

PROCS=$(nproc --all)

export USE_CCACHE=1

ccache -M 100G

LC_ALL=C
export LC_ALL

# Install repo tool
init_repo() {
    mkdir -p ~/bin

    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo

    chmod a+x ~/bin/repo

    export PATH=~/bin:$PATH
}

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
*GKI Kernel CI*

*Device:* \`${DEVICE} (${CODENAME})\`
*Variant:* \`${VARIANT}\`
*Date:* \`${DATE}\`
"
}

# Sync source
sync_source() {

    cd "$WORK_DIR"

    echo "Syncing manifest"

    repo init --depth=1 \
    -u https://github.com/neophyte404/kernel_manifest.git \
    -b main

    repo sync -c -j"${PROCS}" \
    --force-sync \
    --no-clone-bundle \
    --no-tags

    echo "Setting up custom clang"

    rm -rf .repo
    rm -rf prebuilts/clang/host/linux-x86

    git clone \
    --depth=1 \
    --single-branch \
    --no-tags \
    --progress \
    https://gitlab.com/nekoprjkt/aosp-clang.git \
    prebuilts/clang/host/linux-x86/clang-r522817
    
    echo "Done"
}

# Setup KernelSU
setup_ksu() {

    if [ "${VARIANT}" = "Vanilla" ]; then
        echo "Skipping KernelSU"
        return
    fi

    cd "${WORK_DIR}/topaz"

    echo "Applying KernelSU-Next..."

    rm -rf ./KernelSU ./KernelSU-Next ./drivers/kernelsu

    curl -LSs \
    "https://raw.githubusercontent.com/pershoot/KernelSU-Next/dev-susfs/kernel/setup.sh" \
    | bash -s dev-susfs

    if [ ! -L "drivers/kernelsu" ]; then
        ln -sf ../KernelSU-Next drivers/kernelsu
    fi
        echo "Applying SuSFS..."

        git clone --depth=1 \
        https://gitlab.com/simonpunk/susfs4ksu.git \
        -b gki-android13-5.15 \
        susfs

        mkdir -p include/linux fs

        cp -f susfs/kernel_patches/include/linux/susfs.h include/linux/

        cp -f \
        susfs/kernel_patches/include/linux/susfs_def.h \
        include/linux/ || true

        cp -f susfs/kernel_patches/fs/susfs.c fs/

        patch -p1 -F 3 < \
        susfs/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch \
        || echo "Hunks failed but continuing..."

        rm -rf susfs

    echo "KernelSU setup done"
}

# Compile kernel
compile() {

    if [ -d "out" ]; then
        rm -rf out && mkdir -p out
    fi

    cd $WORK_DIR
    export SOURCE_DATE_EPOCH=$(date +%s)
    LTO=thin BUILD_CONFIG=$KERNEL_DIR/build.config.gki.aarch64 build/build.sh

    IMAGE="out/android13-5.15/dist/Image"

    if ! [ -f "${IMAGE}" ]; then

        tg "
*Build failed!*

Please check GitHub Actions logs.
"

        exit 1
    fi

    cd "$WORK_DIR"

    git clone --depth=1 \
    https://github.com/neophyte404/Anykernel3.git \
    "${ANYKERNEL}" \
    -b topaz

    cp "${WORK_DIR}/${IMAGE}" "${ANYKERNEL}/Image"
}

# Make zip
zipping() {

    cd "${ANYKERNEL}"

    ZIPNAME="Neophyte-${CODENAME}-${VARIANT}-${DATE}.zip"

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
init_repo
sendinfo
sync_source
setup_ksu
compile
zipping
push_zip
