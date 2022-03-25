#!/usr/bin/env bash

# Automatically build WSA with root and Magisk
# There will be two root providers: Kernel-assisted and Magisk. We mainly use Magisk root and let Kernel-assisted root as a backup.
# Requirements (May not all needed):
#   sudo coreutils jq sed git grep unzip curl bc binutils-aarch64-linux-gnu bison gcc g++ make llvm lld clang ca-certificates cpio flex gcc-aarch64-linux-gnu gnupg 
#   libelf libncures libssl lsb-release jdk11 python3 e2fsprogs qemu-utils python3-distutils patchelf
# Optional Requirement(s): 
#   aria2: for improved downloading
#   wine/wine64: for merging localized contents
#   cabextract: if you use wine to merge localized contents
#   winetricks: if you use wine to merge localized contents
# Sometimes you may use proxy to connect in someplace. If you meet network problems, you can download files with other dowloader and place file with correct name and at valid place.
# You can set ${ANDROID_SDK_ROOT} to use existing Android SDK.

# Code source: https://github.com/LSPosed/MagiskOnWSA and https://github.com/KiruyaMomochi/wsa-kernel-build

set -e

TARGET_ARCH=x86_64
# Target architecture, x86_64 or arm64
WSA_POS=16709
# Position of WSA Kernel in JSON, if outdated, this script can fix it automatically.
LOG=5
# Log level, from 1 to 5 to get more and more details.
AUTO_CLEAN=0
# Auto remove src and out dir when start script, set it to 0 to disable.
INSTALL_REQS=0
# Auto install requirements, 1 to enable and 0 to disable.
CMDLINETOOLS_BUILD=8092744
# Build number of cmdline-tools, get upgrade at https://developer.android.com/studio#command-tools
LOCALIZED_CONTENTS=1
# Enable/Disable localized contents.

function debug(){
    [[ ${LOG} -gt 4 ]] && echo -e "\033[47;30mDEBG:\033[0m $@"
}
function info(){
    [[ ${LOG} -gt 3 ]] && echo -e "\033[46;1mINFO:\033[0m $@"
}
function warn(){
    [[ ${LOG} -gt 2 ]] && echo -e "\033[43;1mWARN:\033[0m $@"
}
function error(){
    [[ ${LOG} -gt 1 ]] && echo -e "\033[41;1mEROR:\033[0m $@"
}

function get_magisk(){
    MAGISK_ARCH=$1
    TARGET_PATH=$2
    mkdir ${TARGET_PATH}
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagisk64.so ${TARGET_PATH}/magisk64 || \
        (cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagisk32.so ${TARGET_PATH}/magisk32 && warn 'Are you going to use 32 bit Magisk?')
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagiskinit.so ${TARGET_PATH}/magiskinit
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagiskboot.so ${TARGET_PATH}/magiskboot
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libbusybox.so ${TARGET_PATH}/busybox
    if [[ ${MAGISK_ARCH} == 'arm64-v8a' ]]
    then
        cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/armeabi-v7a/libmagisk32.so ${TARGET_PATH}/magisk32
    elif [[ ${MAGISK_ARCH} == 'x86_64' ]]
    then
        cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/x86/libmagisk32.so ${TARGET_PATH}/magisk32
    fi
    if [[ -f ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagiskpolicy.so ]]
    then
        cp ${ROOT}/out/Magisk/app-release.apk.unpacked/lib/${MAGISK_ARCH}/libmagiskpolicy.so ${TARGET_PATH}/magiskpolicy
    else
        ln -sf magiskinit ${TARGET_PATH}/magiskpolicy
    fi
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/assets/boot_patch.sh ${TARGET_PATH}/boot_patch.sh
    cp ${ROOT}/out/Magisk/app-release.apk.unpacked/assets/util_functions.sh ${TARGET_PATH}/util_functions.sh
}
function get_files(){
    URL=$1
    NAME=$2
    info "Downloading file ${NAME}"
    debug "Downloading file ${NAME} with URL ${URL}"
    if [[ ${USE_ARIA2C} -eq 1 ]]
    then
        aria2c --no-conf --daemon=false --continue=true --out=${NAME} ${URL}
    else
        curl -C -L -o ${NAME} ${URL}
    fi
}
function try_get_files(){
    URL=$1
    NAME=$2
    if [[ -f ${NAME} ]]
    then
        warn "File ${NAME} has been downloaded."
    else
        get_files ${URL} ${NAME}
    fi
}

if ! command -v lsb_release > /dev/null 2>&1
then
    command -v apt-get > /dev/null 2>&1 && sudo apt-get install -y lsb-release
    (command -v dnf > /dev/null 2>&1 && sudo dnf install -y redhat-lsb-core) || (command -v yum > /dev/null 2>&1 && sudo yum install -y redhat-lsb-core)
    command -v pacman > /dev/null 2>&1 && sudo pacman -S --needed lsb-release
    # The least requirement, we use lsb-release to check your distribution.
fi
ROOT=${PWD}
USE_ARIA2C=0
command -v aria2c > /dev/null 2>&1 && info 'aria2 found, we will use it for better download experience.' && export USE_ARIA2C=1
DIST=$(lsb_release -is)
CURRENT_ARCH=$(uname -m)
case ${CURRENT_ARCH} in
    "aarch64")
        CURRENT_ARCH='arm64-v8a'
        ;;
    "armv7l")
        CURRENT_ARCH='armeabi-v7a'
        ;;
esac
if [[ ${CURRENT_ARCH} =~ 64 ]]
then
    LINKER=linker64
else
    LINKER=linker
fi
debug "Current arch is ${CURRENT_ARCH}, linker is ${LINKER}"
if [[ ${INSTALL_REQS} -eq 1 ]]
then
    info 'Installing Requirements...'
    case ${DIST} in
    "Ubuntu" | "Debian")
        LLVM_VER=13
        curl -LO https://apt.llvm.org/llvm.sh && bash llvm.sh ${LLVM_VER} && rm llvm.sh
        sudo apt-get upgrade && sudo apt-get install -y \
            bc binutils-aarch64-linux-gnu bison build-essential ca-certificates cpio flex gcc-aarch64-linux-gnu gnupg libelf-dev libncurses-dev libssl-dev \
            jq sed git grep unzip curl coreutils openjdk-11-jdk python3 clang-${LLVM_VER} lld-${LLVM_VER} llvm-${LLVM_VER} e2fsprogs qemu-utils python3-distutils \
            patchelf
        for item in llvm-strip llvm-nm llvm-objcopy llvm-objdump llvm-objstrip llvm-as llvm-addr2line llvm-ar clang ld.lld
        do
            if [[ ${item} == clang ]]
            then
                sudo update-alternatives --install /usr/bin/${item} ${item} /usr/bin/${item}-${LLVM_VER} 1 --slave /usr/bin/${item}++ ${item}++ /usr/bin/${item}++-${LLVM_VER} || \
                (sudo ln -sf ${item}-${LLVM_VER} /usr/bin/${item} && sudo ln -sf ${item}++-${LLVM_VER} /usr/bin/${item}++)
            else
                sudo update-alternatives --install /usr/bin/${item} ${item} /usr/bin/${item}-${LLVM_VER} 1 || sudo ln -sf ${item}-${LLVM_VER} /usr/bin/${item}
            fi
        done
        # Maybe I miss something, these packages need manual operations.
        ;;
    "CentOS" | "RedHat.*" | "Fedora")
        PKM=yum
        command -v dnf > /dev/null 2>&1 && PKM=dnf
        [[ ${DIST} == "CentOS" ]] && sudo ${PKM} install -y epel-release
        [[ ${DIST} =~ RedHat.* ]] && warn 'You are using RedHat and may see some packages missing, you have to fix them manually.'
        sudo ${PKM} install -y \
            bc bison ca-certificates cpio flex gcc-c++-aarch64-linux-gnu gnupg elfutils-libelf-devel ncurses-devel openssl-devel clang llvm lld \
            jq sed git grep unzip curl coreutils java-11-openjdk-devel python3 e2fsprogs qemu patchelf && \
            sudo ${PKM} groupinstall -y "Development Tools" "Development Libraries"
        ;;
    "Arch")
        sudo pacman -S --needed \
            bc aarch64-linux-gnu-binutils bison base-devel ca-certificates cpio flex aarch64-linux-gnu-gcc gnupg libelf ncurses openssl jq sed git grep \
            unzip curl coreutils jdk11-openjdk python e2fsprogs clang llvm lld qemu patchelf
        ;;
        # TODO: Fix Package name and extra operation(s) in non-Arch dists because I am not using them and I am not sure if these names and operations are right...
    "*")
        warn "Unsupported Distribution, you have to check your dependencies manually!"
        ;;
    esac
fi
[[ ${AUTO_CLEAN} -eq 1 ]] && [[ -d src ]] && rm -rf src
[[ -d out ]] && rm -rf out
mkdir -p src
mkdir -p out/target/${TARGET_ARCH}
[[ -z ${ANDROID_SDK_ROOT} ]] && export ANDROID_SDK_ROOT=${ROOT}/src/AndroidSDK && warn "You do not have \${ANDROID_SDK_ROOT} set, we will use ${ANDROID_SDK_ROOT} as default"
export ANDROID_SDK_HOME=${ANDROID_SDK_ROOT}
mkdir -p ${ANDROID_SDK_ROOT}
java --version | grep -q 'openjdk 11' || warn 'You may not set jdk 11 in ${PATH}, we may meet problems when building.'
cd src
info 'Getting libraries to patch magiskpolicy...'
mkdir -p linker/${CURRENT_ARCH}
if [[ ${CURRENT_ARCH} == 'x86_64' ]]
then
    for file in linker64 libc.so libdl.so libm.so
    do
        try_get_files https://github.com/LSPosed/MagiskOnWSA/raw/main/linker/${file} ${ROOT}/src/linker/${CURRENT_ARCH}/${file}
        if [[ ${file} == 'linker64' ]]
        then
            chmod +x ${ROOT}/src/linker/${CURRENT_ARCH}/${file}
        fi
    done
else
    error "No supported files to patch magiskpolicy, you need to get linker/linker64, libc.so, libdl.so, libm.so yourself and put them at ${ROOT}/src/linker/${CURRENT_ARCH}"
fi
info 'Getting WSA Kernel Sources...'
if [[ ! -f WSA-Linux-Kernel.zip ]]
then
    data=$(curl -L https://3rdpartysource.microsoft.com/downloads)
    name=$(echo ${data} | jq ".[${WSA_POS}].dependency" | sed "s/\"//g")
    debug ${name}
    if [[ ${name} == 'WSA-Linux-Kernel' ]]
    then
        info "Using \${WSA_POS} to speedup."
        url=$(echo ${data} | jq ".[${WSA_POS}].url" | sed "s/\"//g")
    else
        warn "Failed to use \${WSA_POS} to speedup, we will check it one by one and it will be very slow."
        pos=0
        for row in $(echo ${data} | jq -r '.[] | @base64')
        do
            item=$(echo ${row} | base64 --decode)
            name=$(echo ${item} | jq -r '.dependency')
            if [[ ${name} == 'WSA-Linux-Kernel' ]]
            then
                url=$(echo ${item} | jq -r '.url')
                break
            else
                ((pos++))
            fi
        done
        info 'Updating ${WSA_POS} for speedup...'
        pos=$(echo ${pos} | sed -r 's/0*([0-9])/\1/')
        debug "New pos is ${pos}"
        sed -i "16s/WSA_POS=.*/WSA_POS=${pos}/" ${ROOT}/$0
    fi
    if [[ -z ${url} ]]
    then
        error 'Cannot find URL of Kernel source.'
        exit 1
    else
        info "Getting WSA-Linux-Kernel.zip with URL ${url}"
        get_files ${url} WSA-Linux-Kernel.zip
    fi
else
    info 'Kernel source has been downloaded.'
fi
info 'Getting Kernel-SU Module...'
git clone --depth=1 https://github.com/LSPosed/WSA-Kernel-SU || warn 'There seems that folder WSA-Kernel-SU already exists, we skip cloning.'
info 'Getting Magisk source...'
git clone --depth=1 --recurse-submodules https://github.com/topjohnwu/Magisk || warn 'There seems that folder Magisk already exists, we skip cloning.'
info 'Getting Riru Magisk module source...'
git clone --depth=1 https://github.com/RikkaApps/Riru || warn 'There seems that folder Riru already exists, we skip cloning.'
info 'Getting .msix file...'
if [[ ! -f ${ROOT}/src/WSA.msixbundle ]]
then
    mainpack=$(curl -s -d "type=url&url=https://www.microsoft.com/p/windows-subsystem-for-android/9p3395vx91nr&ring=WIS&lang=en-US" -X POST "https://store.rg-adguard.net/api/GetFiles" | \
            awk '/<table class="tftable" border="1" align="center">/, /<\/table>/' | sed '/<\/table><script type="text\/javascript">/d;/<table class="tftable" border="1" align="center">/d' | \
            awk 'NR>5' | sed '/<\/tr><\/thead>/d;/^$/d' | tail -n 1)
    packurl=$(echo ${mainpack} | grep -o '<a href=".*" rel' | sed 's/<a href="//;s/" rel//')
    try_get_files ${packurl} ${ROOT}/src/WSA.msixbundle
fi
if [[ ! -d ${ANDROID_SDK_ROOT}/cmdline-tools/latest ]]
then
    try_get_files https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINETOOLS_BUILD}_latest.zip ${ROOT}/src/cmdline-tools.zip
    info 'Unpacking cmdline-tools...'
    mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools/temp
    unzip -q -o 'cmdline-tools.zip' -d ${ANDROID_SDK_ROOT}/cmdline-tools/temp
    mv ${ANDROID_SDK_ROOT}/cmdline-tools/temp/cmdline-tools/* ${ANDROID_SDK_ROOT}/cmdline-tools/temp
    rm -rf ${ANDROID_SDK_ROOT}/cmdline-tools/temp/cmdline-tools
    if [[ ! -d ${ANDROID_SDK_ROOT}/licences ]]
    then
        info 'Accepting Android SDK Licences...'
        yes | ${ANDROID_SDK_ROOT}/cmdline-tools/temp/bin/sdkmanager --licenses
    fi
    ${ANDROID_SDK_ROOT}/cmdline-tools/temp/bin/sdkmanager --install 'cmdline-tools;latest'
    rm -rf ${ANDROID_SDK_ROOT}/cmdline-tools/temp
fi
info 'Unpacking Kernel source...'
unzip -q -o 'WSA-Linux-Kernel.zip' -d ${PWD}
cd WSA-Linux-Kernel
info 'Patching Kernel...'
cd ${ROOT}/src/WSA-Kernel-SU
KERNEL_BASE=${ROOT}/src/WSA-Linux-Kernel/drivers/base
SU_BASE=${ROOT}/src/WSA-Kernel-SU/drivers/base/superuser
grep -q ASSISTED_SUPERUSER ${KERNEL_BASE}/Kconfig || cat ${SU_BASE}/Kconfig >> ${KERNEL_BASE}/Kconfig
grep -q ASSISTED_SUPERUSER ${KERNEL_BASE}/Makefile || cat ${SU_BASE}/Makefile >> ${KERNEL_BASE}/Makefile
cp ${SU_BASE}/superuser.c ${KERNEL_BASE}/superuser.c
info 'Compiling Kernel...'
cd ${ROOT}/src/WSA-Linux-Kernel
case ${TARGET_ARCH} in
    "arm64")
        cp configs/arm64/kernel_defconfig .config
        export CROSS_COMPILE=aarch64-linux-gnu-
        export ARCH=arm64
        ;;
    "x86_64")
        cp configs/x86/kernel_defconfig .config
        ;;
    "*")
        warn 'Invalid Target architecture, We will use x86_64 as default.'
        cp configs/x86/kernel_defconfig .config
        ;;
esac
sed -i "s/CONFIG_LOCALVERSION=\"-windows-subsystem-for-android\"/CONFIG_LOCALVERSION=\"-wsa-root\"/" .config
grep -q CONFIG_ASSISTED_SUPERUSER .config || sed -i "1i CONFIG_ASSISTED_SUPERUSER=y" .config
export LLVM=1
make olddefconfig
make bzImage -j$(nproc)
info 'Unpacking .msix file'
cd ${ROOT}/src
unzip -o -d ${ROOT}/src/WSA-Package WSA.msixbundle
cd WSA-Package
if [[ ${TARGET_ARCH} = "arm64" ]]
then
    pack=$(ls *ARM64*)
    kernel="${ROOT}/src/WSA-Linux-Kernel/arch/arm64/boot/bzImage"
    MAGISK_ARCH=arm64-v8a
else
    pack=$(ls *x64*)
    kernel="${ROOT}/src/WSA-Linux-Kernel/arch/x86_64/boot/bzImage"
    MAGISK_ARCH=x86_64
fi
unzip -q -o ${pack} -d ${ROOT}/out/WSA-Deploy
mkdir -p ${ROOT}/src/lang/pri ${ROOT}/src/lang/xml ${ROOT}/src/WSA-Package/lang
for langfile in $(ls *language*)
do 
    lang=$(echo ${langfile} | cut -d . -f 4 | cut -d _ -f 2 | sed s/language-//)
    mkdir -p lang/${lang}
    unzip -o -d lang/${lang} ${langfile}
    cp lang/${lang}/resources.pri ${ROOT}/src/lang/pri/${lang}.pri
    cp lang/${lang}/AppxManifest.xml ${ROOT}/src/lang/xml/${lang}.xml
done
cd ${ROOT}/src/lang
cp ${ROOT}/out/WSA-Deploy/resources.pri ${ROOT}/src/lang/pri/en-us.pri
cp ${ROOT}/out/WSA-Deploy/AppxManifest.xml ${ROOT}/src/lang/xml/en-us.xml
tee priconfig.xml <<EOF
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<resources targetOsVersion="10.0.0" majorVersion="1">
    <index root="\" startIndexAt="\">
        <indexer-config type="folder" foldernameAsQualifier="true" filenameAsQualifier="true" qualifierDelimiter="."/>
        <indexer-config type="PRI"/>
    </index>
</resources>
EOF
if [[ ${LOCALIZED_CONTENTS} -eq 1 ]] && command -v wine64 > /dev/null 2>&1
then
    info 'Wine64 detected, merging localized contents...'
    mkdir -p ${ROOT}/src/wine ${ROOT}/src/wine-prefixes 
    cd ${ROOT}/src/wine
    export WINEPREFIX=${ROOT}/src/wine-prefixes
    export WINE=wine64
    if ! command -v winetricks > /dev/null 2>&1
    then
        info 'Getting winetricks from GitHub...'
        try_get_files https://github.com/Winetricks/winetricks/raw/master/src/winetricks ${ROOT}/src/wine/winetricks
        chmod +x ${ROOT}/src/wine/winetricks
        WINETRICKS=${ROOT}/src/wine/winetricks
    else
        WINETRICKS=winetricks
        info 'Using existing winetricks...'
    fi
    try_get_files https://github.com/LSPosed/MagiskOnWSA/raw/main/wine/makepri.exe ${ROOT}/src/wine/makepri.exe
    cd ${ROOT}/src/lang
    if [[ ! -f ${ROOT}/src/lang/resources.pri ]]
    then
        ${WINETRICKS} msxml6
        wine64 ${ROOT}/src/wine/makepri.exe new /pr pri /in MicrosoftCorporationII.WindowsSubsystemForAndroid /cf priconfig.xml /of resources.pri /o
    else
        warn "File ${ROOT}/lang/resources.pri found, we use this existing one instead generate ourself."
    fi
    cp ${ROOT}/out/WSA-Deploy/AppxManifest.xml AppxManifest.xml
    sed -i -zE "s/<Resources.*Resources>/<Resources>\n$(cat xml/* | grep -Po '<Resource [^>]*/>' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\$/\\$/g' | sed 's/\//\\\//g')\n<\/Resources>/g" AppxManifest.xml
    cp resources.pri ${ROOT}/out/WSA-Deploy/resources.pri
    cp AppxManifest.xml ${ROOT}/out/WSA-Deploy/AppxManifest.xml
fi
cd ${ROOT}/out/WSA-Deploy
rm -rf '[Content_Types].xml' 'AppxBlockMap.xml' 'AppxSignature.p7x' 'AppxMetadata'
cp ${kernel} 'Tools/kernel'
cd ${ROOT}/src
info 'WSA with root support build successful!'
cd Magisk
info 'Patching Magisk...'
git apply ${ROOT}/magisk-wsa.patch || warn 'Patch Magisk failed. This may because the patch has been applied.'
info 'Building Magisk...'
[[ ! -d ${ANDROID_SDK_ROOT}/ndk/magisk ]] && python3 build.py -v ndk
python3 build.py -vr all
mkdir -p ${ROOT}/out/Magisk
cp out/app-release.apk ${ROOT}/out/Magisk/app-release.apk
info 'Patching Riru Magisk module...'
cd ${ROOT}/src/Riru
git apply ${ROOT}/riru-wsa.patch || warn 'Patch Riru failed. This may because the patch has been applied.'
info 'Building Riru Magisk module...'
rm -rf out
bash -c './gradlew :riru:assembleRelease'
cd out
riru_zip=$(ls *.zip)
cp ${riru_zip} ${ROOT}/out/target/${TARGET_ARCH}
info 'Generating PowerShell script for deploying in Windows...'
cat > ${ROOT}/out/target/${TARGET_ARCH}/deploy.ps1 << 'EOF'
# Automated Install script by Mioki
# http://github.com/okibcn
function Test-Administrator {
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]\$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return \$user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}
function Finish {
    Clear-Host
    Start-Process "wsa://com.topjohnwu.magisk"
    Start-Process "wsa://com.android.vending"
}
if (-not (Test-Administrator)) {
    \$proc = Start-Process -PassThru -WindowStyle Hidden -Verb RunAs powershell.exe -Args "-executionpolicy bypass -command Set-Location '\$PSScriptRoot'; &'\$PSCommandPath' EVAL"
    \$proc.WaitForExit()
    if (\$proc.ExitCode -ne 0) {
        Clear-Host
        Write-Warning "Failed to launch start as Administrator\`r\`nPress any key to exit"
        \$null = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    }
    exit
}
elseif ((\$args.Count -eq 1) -and (\$args[0] -eq "EVAL")) {
    Start-Process powershell.exe -Args "-executionpolicy bypass -command Set-Location '\$PSScriptRoot'; &'\$PSCommandPath'"
    exit
}
reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"
\$VMP = Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform'
if (\$VMP.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -NoRestart -FeatureName 'VirtualMachinePlatform'
    Clear-Host
    Write-Warning "Need restart to enable virtual machine platform\`r\`nPress y to restart or press any key to exit"
    \$key = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -eq \$key.Character) {
        Restart-Computer -Confirm
    }
    Else {
        exit 1
    }
}
Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path vclibs.appx
Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path xaml.appx
\$Installed = \$null
\$Installed = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid'
If ((\$null -ne \$Installed) -and (-not (\$Installed.IsDevelopmentMode))) {
    Clear-Host
    Write-Warning "There is already one installed WSA. Please uninstall it first.\`r\`nPress y to uninstall existing WSA or press any key to exit"
    \$key = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -eq \$key.Character) {
        Remove-AppxPackage -Package \$Installed.PackageFullName
    }
    Else {
        exit 1
    }
}
Clear-Host
Write-Host "Installing MagiskOnWSA..."
Stop-Process -Name "wsaclient" -ErrorAction "silentlycontinue"
Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\WSA-Deploy\AppxManifest.xml
if (\$?) {
    Finish
}
Elseif (\$null -ne \$Installed) {
    Clear-Host
    Write-Host "Failed to update, try to uninstall existing installation while preserving userdata..."
    Remove-AppxPackage -PreserveApplicationData -Package \$Installed.PackageFullName
    Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\AppxManifest.xml
    if (\$?) {
        Finish
    }
}
Write-Host "All Done\`r\`nPress any key to exit"
\$null = \$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
EOF
info 'Intergrating Magisk, this operation also needs root privilege...'
cd ${ROOT}/out/WSA-Deploy
cp -a ${ROOT}/out/WSA-Deploy ${ROOT}/out/target/${TARGET_ARCH}
cp system.img system.img.orig
cp system_ext.img system_ext.img.orig
cp vendor.img vendor.img.orig
cp product.img product.img.orig
cp userdata.vhdx userdata.vhdx.orig
qemu-img convert -O raw userdata.vhdx userdata.img
resize2fs system.img 1024M
resize2fs product.img 1024M
resize2fs system_ext.img 108M
resize2fs vendor.img 320M
sudo mkdir system
sudo mount -o loop system.img system
sudo mount -o loop vendor.img system/vendor
sudo mount -o loop product.img system/product
sudo mount -o loop system_ext.img system/system_ext
sudo mount -o loop userdata.img system/data
sudo mkdir system/sbin
sudo chcon --reference system/init.environ.rc system/sbin || \
    ([[ ${DIST} == "Arch" ]] && warn 'Building on Arch Linux need SELinux enabled to work properly, you can find more at https://wiki.archlinux.org/title/SELinux') || \
    warn 'Failed to set SELinux context.'
sudo chown root:root system/sbin
sudo chmod 0700 system/sbin
sudo tee -a system/sbin/loadpolicy.sh <<EOF
#!/system/bin/sh
restorecon -R /data/adb/magisk
for module in \$(ls /data/adb/modules); do
    if ! [ -f "/data/adb/modules/\$module/disable" ] && [ -f "/data/adb/modules/\$module/sepolicy.rule" ]; then
        /sbin/magiskpolicy --live --apply "/data/adb/modules/\$module/sepolicy.rule"
    fi
done
EOF
unzip -q -o ${ROOT}/out/Magisk/app-release.apk -d ${ROOT}/out/Magisk/app-release.apk.unpacked
cp ${ROOT}/out/Magisk/app-release.apk ${ROOT}/out/target/${TARGET_ARCH}/Magisk.apk
get_magisk ${MAGISK_ARCH} magisk
get_magisk ${CURRENT_ARCH} magisk.${CURRENT_ARCH}
sudo cp magisk/* system/sbin/
sudo mkdir -p system/data/adb/magisk
sudo chmod -R 700 system/data/adb
sudo cp magisk/* system/data/adb/magisk/
sudo find system/data/adb/magisk -type f -exec chmod 0755 {} \;
sudo cp ${ROOT}/out/Magisk/app-release.apk system/data/adb/magisk/magisk.apk
sudo find system/sbin -type f -exec chmod 0755 {} \;
sudo find system/sbin -type f -exec chown root:root {} \;
sudo find system/sbin -type f -exec chcon --reference system/product {} \; || warn 'Failed to set SELinux context.'
sudo patchelf --replace-needed libc.so "${ROOT}/src/linker/${CURRENT_ARCH}/libc.so" ./magisk.${CURRENT_ARCH}/magiskpolicy || true
sudo patchelf --replace-needed libm.so "${ROOT}/src/linker/${CURRENT_ARCH}/libm.so" ./magisk.${CURRENT_ARCH}/magiskpolicy || true
sudo patchelf --replace-needed libdl.so "${ROOT}/src/linker/${CURRENT_ARCH}/libdl.so" ./magisk.${CURRENT_ARCH}/magiskpolicy || true
sudo patchelf --set-interpreter "${ROOT}/src/linker/${CURRENT_ARCH}/${LINKER}" ./magisk.${CURRENT_ARCH}/magiskpolicy || true
chmod +x magisk.${CURRENT_ARCH}/magiskpolicy
echo '/dev/wsa-magisk(/.*)?    u:object_r:magisk_file:s0' | sudo tee -a system/vendor/etc/selinux/vendor_file_contexts
echo '/data/adb/magisk(/.*)?   u:object_r:magisk_file:s0' | sudo tee -a system/vendor/etc/selinux/vendor_file_contexts
sudo ./magisk.${CURRENT_ARCH}/magiskpolicy --load system/vendor/etc/selinux/precompiled_sepolicy --save system/vendor/etc/selinux/precompiled_sepolicy \
    --magisk "allow * magisk_file lnk_file *"
sudo tee -a system/system/etc/init/hw/init.rc <<EOF
on post-fs-data
    start logd
    start adbd
    mkdir /dev/wsa-magisk
    mount tmpfs tmpfs /dev/wsa-magisk mode=0755
    copy /sbin/magisk64 /dev/wsa-magisk/magisk64
    chmod 0755 /dev/wsa-magisk/magisk64
    symlink ./magisk64 /dev/wsa-magisk/magisk
    symlink ./magisk64 /dev/wsa-magisk/su
    symlink ./magisk64 /dev/wsa-magisk/resetprop
    copy /sbin/magisk32 /dev/wsa-magisk/magisk32
    chmod 0755 /dev/wsa-magisk/magisk32
    copy /sbin/magiskinit /dev/wsa-magisk/magiskinit
    chmod 0755 /dev/wsa-magisk/magiskinit
    symlink ./magiskinit /dev/wsa-magisk/magiskpolicy
    mkdir /dev/wsa-magisk/.magisk 700
    mkdir /dev/wsa-magisk/.magisk/mirror 700
    mkdir /dev/wsa-magisk/.magisk/block 700
    rm /dev/.magisk_unblock
    start IhhslLhHYfse
    start FAhW7H9G5sf
    wait /dev/.magisk_unblock 40
    rm /dev/.magisk_unblock
service IhhslLhHYfse /system/bin/sh /sbin/loadpolicy.sh
    user root
    seclabel u:r:magisk:s0
    oneshot
service FAhW7H9G5sf /dev/wsa-magisk/magisk --post-fs-data
    user root
    seclabel u:r:magisk:s0
    oneshot
service HLiFsR1HtIXVN6 /dev/wsa-magisk/magisk --service
    class late_start
    user root
    seclabel u:r:magisk:s0
    oneshot
on property:sys.boot_completed=1
    start YqCTLTppv3ML
service YqCTLTppv3ML /dev/wsa-magisk/magisk --boot-complete
    user root
    seclabel u:r:magisk:s0
    oneshot
EOF
sudo umount system/system_ext
sudo umount system/product
sudo umount system/vendor
sudo umount system/data
sudo umount system
sudo rm -rf system
qemu-img convert -o subformat=dynamic -f raw -O vhdx userdata.img userdata.vhdx
rm -rf ${ROOT}/out/Magisk/app-release.apk.unpacked userdata.img magisk magisk.${CURRENT_ARCH}
for file in system.img system_ext.img product.img vendor.img userdata.vhdx
do
    cp ${file} ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
    mv ${file}.orig ${file}
    if [[ ${file} != userdata.vhdx ]]
    then
        e2fsck -yf ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
        resize2fs -M ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
    fi
done
# Recover backup, you can use these ${ROOT}/out/WSA-Deploy folder for installing WSA with only Kernel-assisted su 
# and deploy Magisk emulator, which is the traditional way to use Magisk on WSA.
cd ${ROOT}
info "All jobs are done, you can copy ${ROOT}/out/target/${TARGET_ARCH} to Windows and run deploy.ps1 for deploying."
