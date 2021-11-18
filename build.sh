#!/usr/bin/env bash

# Automatically build WSA with root and Magisk
# There will be two root providers: Kernel-assisted and Magisk. We mainly use Magisk root and let Kernel-assisted root as a backup.
# Requirements:
# sudo coreutils jq sed git grep unzip curl bc binutils-aarch64-linux-gnu bison gcc g++ make llvm lld clang ca-certificates cpio flex gcc-aarch64-linux-gnu gnupg libelf libncures libssl lsb-release jdk11 python3 e2fsprogs
# Optional Requirement(s): 
# aria2: for improved downloading
# Sometimes you may use proxy to connect in someplace. If you meet network problems, you can download files with other dowloader and place file with correct name and at valid place.
# You can set ${ANDROID_SDK_ROOT} to use existing Android SDK.

# Code source: https://github.com/LSPosed/MagiskOnWSA and https://github.com/KiruyaMomochi/wsa-kernel-build

TARGET_ARCH=x86_64
# Target architecture, x86_64 or arm64
WSA_POS=15699
# Position of WSA Kernel in JSON, if outdated, this script can fix it automatically.
LOG=5
# Log level, from 1 to 5 to get more and more details.
AUTO_CLEAN=0
# Auto remove src and out dir when start script, set it to 0 to disable.
INSTALL_REQS=0
# Auto install requirements, 1 to enable and 0 to disable.

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

command -v apt-get > /dev/null 2>&1 && sudo apt-get install -y lsb-release
(command -v dnf > /dev/null 2>&1 && sudo dnf install -y redhat-lsb-core) || (command -v yum > /dev/null 2>&1 && sudo yum install -y redhat-lsb-core)
command -v pacman > /dev/null 2>&1 && sudo pacman -S --needed lsb-release
# The least requirement, we use lsb-release to check your distribution.
ROOT=${PWD}
USE_ARIA2C=0
CURRENT_ARCH=$(uname -m)
DIST=$(lsb_release -is)
case ${CURRENT_ARCH} in
    "aarch64")
        CURRENT_ARCH='arm64-v8a'
        ;;
    "armv7l")
        CURRENT_ARCH='armeabi-v7a'
        ;;
esac
debug "Current arch is ${CURRENT_ARCH}"
command -v aria2c > /dev/null 2>&1 && info 'aria2 found, we will use it for better download experience.' && export USE_ARIA2C=1
if [[ ${INSTALL_REQS} -eq 1 ]]
then
    info 'Installing Requirements...'
    case ${DIST} in
    "Ubuntu" | "Debian")
        LLVM_VER=13
        curl -LO https://apt.llvm.org/llvm.sh && bash llvm.sh ${LLVM_VER} && rm llvm.sh
        sudo apt-get upgrade && sudo apt-get install -y \
            bc binutils-aarch64-linux-gnu bison build-essential ca-certificates cpio flex gcc-aarch64-linux-gnu gnupg libelf-dev libncurses-dev libssl-dev \
            jq sed git grep unzip curl coreutils openjdk-11-jdk python3 clang-${LLVM_VER} lld-${LLVM_VER} llvm-${LLVM_VER} e2fsprogs
        for item in llvm-strip llvm-nm llvm-objcopy llvm-objstrip llvm-as llvm-addr2line llvm-ar clang ld.lld
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
            jq sed git grep unzip curl coreutils java-11-openjdk-devel python3 e2fsprogs && sudo ${PKM} groupinstall -y "Development Tools" "Development Libraries"
        ;;
    "Arch")
        sudo pacman -S --needed \
            bc aarch64-linux-gnu-binutils bison base-devel ca-certificates cpio flex aarch64-linux-gnu-gcc gnupg libelf ncurses openssl jq sed git grep \
            unzip curl coreutils jdk11-openjdk python e2fsprogs clang llvm lld
        ;;
        # TODO: Fix Package name and extra operation(s) in non-Arch dists because I am not using them and I am not sure if these names and operations are right...
    "*")
        warn "Unsupported Distribution, you have to check your dependencies manually!"
        ;;
    esac
fi
[[ ${AUTO_CLEAN} -eq 1 ]] && [[ -d out ]] && rm -rf out && [[ -d src ]] && rm -rf src
mkdir -p src
mkdir -p out/target/${TARGET_ARCH}
[[ -z ${ANDROID_SDK_ROOT} ]] && export ANDROID_SDK_ROOT=${ROOT}/src/AndroidSDK && warn "You do not have \${ANDROID_SDK_ROOT} set, we will use ${ANDROID_SDK_ROOT} as default"
export ANDROID_SDK_HOME=${ANDROID_SDK_ROOT}
mkdir -p ${ANDROID_SDK_ROOT}
java --version | grep -q 'openjdk 11' || warn 'You may not set jdk 11 in ${PATH}, we may meet problems when building.'
cd src
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
        if [[ ${USE_ARIA2C} -eq 1 ]]
        then
            aria2c --no-conf --daemon=false --continue=true --out=WSA-Linux-Kernel.zip ${url}
        else
            curl -L -C ${url} -o WSA-Linux-Kernel.zip
        fi
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
if [[ ! -f WSA.msixbundle ]]
then
    mainpack=$(curl -d "type=url&url=https://www.microsoft.com/p/windows-subsystem-for-android/9p3395vx91nr&ring=WIS&lang=zh-CN" -X POST "https://store.rg-adguard.net/api/GetFiles" | \
            awk '/<table class="tftable" border="1" align="center">/, /<\/table>/' | sed '/<\/table><script type="text\/javascript">/d;/<table class="tftable" border="1" align="center">/d' | \
            awk 'NR>5' | sed '/<\/tr><\/thead>/d;/^$/d' | tail -n 1)
    packurl=$(echo ${mainpack} | grep -o '<a href=".*" rel' | sed 's/<a href="//;s/" rel//')
    debug "Use ${packurl} to get WSA.msixbundle"
    if [[ ${USE_ARIA2C} -eq 1 ]]
    then
        aria2c --no-conf --daemon=false --continue=true --out=WSA.msixbundle ${packurl}
    else
        curl -C -L ${packurl} -o WSA.msixbundle
    fi
else
    info "WSA.msixbundle has been downloaded."
fi
if [[ ! -d ${ANDROID_SDK_ROOT}/cmdline-tools/latest ]]
then
    info 'Bootstrapping cmdline tools...'
    if [[ ${USE_ARIA2C} -eq 1 ]]
    then
        aria2c --no-conf --daemon=false --continue=true --out=cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip
    else
        curl -L -C -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-7583922_latest.zip
    fi
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
KVER=$(make kernelversion | cut -d . -f 1,2)
info 'Patching Kernel...'
cd ${ROOT}/src/WSA-Kernel-SU
git apply ${ROOT}/Kconfig.patch
KERNEL_BASE=${ROOT}/src/WSA-Linux-Kernel/drivers/base
SU_BASE=${ROOT}/src/WSA-Kernel-SU/drivers/base/superuser
grep -q ASSISTED_SUPERUSER ${KERNEL_BASE}/Kconfig || cat ${SU_BASE}/Kconfig >> ${KERNEL_BASE}/Kconfig
grep -q ASSISTED_SUPERUSER ${KERNEL_BASE}/Makefile || cat ${SU_BASE}/Makefile >> ${KERNEL_BASE}/Makefile
cp ${SU_BASE}/superuser.c ${KERNEL_BASE}/superuser.c
info 'Compiling Kernel...'
cd ${ROOT}/src/WSA-Linux-Kernel
case ${TARGET_ARCH} in
    "arm64")
        cp configs/wsa/config-wsa-arm64-${KVER} .config
        export CROSS_COMPILE=aarch64-linux-gnu-
        export ARCH=arm64
        ;;
    "x86_64")
        cp configs/wsa/config-wsa-${KVER} .config
        ;;
    "*")
        warn 'Invalid Target architecture, We will use x86_64 as default.'
        cp configs/wsa/config-wsa-${KVER} .config
        ;;
esac
sed -i "s/CONFIG_LOCALVERSION=\"-windows-subsystem-for-android\"/CONFIG_LOCALVERSION=\"-wsa-root\"/" .config
grep -q CONFIG_ASSISTED_SUPERUSER .config || sed -i "1i CONFIG_ASSISTED_SUPERUSER=y" .config
export LLVM=1
yes | make oldconfig
make bzImage -j$(nproc)
info 'Unpacking .msix file'
cd ${ROOT}/src
unzip -o WSA.msixbundle -d ${ROOT}/src/WSA-Package
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
cd ${ROOT}/out/WSA-Deploy
rm -rf '[Content_Types].xml' 'AppxBlockMap.xml' 'AppxSignature.p7x' 'AppxMetadata'
cp ${kernel} 'Tools/kernel'
cd ${ROOT}/src
info 'WSA with root support build successful!'
cd Magisk
info 'Patching Magisk...'
git apply ${ROOT}/magisk-wsa.patch
info 'Building Magisk...'
[[ ! -d ${ANDROID_SDK_ROOT}/ndk/magisk ]] && python3 build.py -v ndk
python3 build.py -v stub
python3 build.py -v emulator
mkdir -p ${ROOT}/out/Magisk
cp scripts/emulator.sh ${ROOT}/out/Magisk/emulator.sh
cp out/app-debug.apk ${ROOT}/out/Magisk/app-debug.apk
cp native/out/${MAGISK_ARCH}/busybox ${ROOT}/out/Magisk/busybox
info 'Patching Riru Magisk module...'
cd ${ROOT}/src/Riru
git apply ${ROOT}/riru-wsa.patch
info 'Building Riru Magisk module...'
rm -rf out
bash -c './gradlew :riru:assembleRelease'
cd out
riru_zip=$(ls *.zip)
cp ${riru_zip} ${ROOT}/out/target/${TARGET_ARCH}
info 'Generating PowerShell script for deploying in Windows...'
cat > ${ROOT}/out/target/${TARGET_ARCH}/deploy.ps1 << 'EOF'
#Requires -RunAsAdministrator
if ($null -eq (Get-Command "adb" -ErrorAction SilentlyContinue)){
    Write-Host 'No ADB Executable in \$PATH found.'
    exit 1
}
Add-AppxPackage -Register WSA-Deploy/AppxManifest.xml
Write-Host 'We need you to start WSA Settings App and enable Developer Mode manually. For more stablility, you can start one app such as File Browser or Amazon Store.'
Read-Host 'When you are ready, press Enter:'
adb connect 127.0.0.1:58526
adb -s 127.0.0.1:58526 install Magisk.apk
Write-Host 'We need you to start Magisk app installed in your Start Menu, it will remind you to fix Magisk environment and restart WSA.'
Read-Host 'When WSA restarted (you can start Magisk app again to test), press Enter:'
adb connect 127.0.0.1:58526
adb -s 127.0.0.1:58526 push ${riru_zip} /data/local/tmp
adb -s 127.0.0.1:58526 shell sh su -c 'magisk --install-module /data/local/tmp/${riru_zip}'
adb -s 127.0.0.1:58526 reboot userspace
Write-Host 'Deploy Completed and WSA will be restarted again. Now you can download LSPosed module and install to Magisk.'
EOF
sed -i "s/\${riru_zip}/${riru_zip}/g" ${ROOT}/out/target/${TARGET_ARCH}/deploy.ps1
info 'Intergrating Magisk, this operation also needs root privilege...'
[[ ${DIST} == "Arch" ]] && warn 'Building on Arch Linux need SELinux enabled to work properly, you can find more at https://wiki.archlinux.org/title/SELinux'
cd ${ROOT}/out/WSA-Deploy
cp -a ${ROOT}/out/WSA-Deploy ${ROOT}/out/target/${TARGET_ARCH}
cp system.img system.img.orig
cp system_ext.img system_ext.img.orig
cp vendor.img vendor.img.orig
cp product.img product.img.orig
resize2fs system.img 1024M
resize2fs product.img 1024M
resize2fs system_ext.img 108M
resize2fs vendor.img 320M
sudo mkdir system
sudo mount -o loop system.img system
sudo mount -o loop vendor.img system/vendor
sudo mount -o loop product.img system/product
sudo mount -o loop system_ext.img system/system_ext
sudo mkdir system/sbin
sudo chcon --reference system/init.environ.rc system/sbin
sudo chown root:root system/sbin
sudo chmod 0700 system/sbin
sudo tee -a system/sbin/loadpolicy.sh <<EOF
#!/system/bin/sh
for module in \$(ls /data/adb/modules); do
    if ! [ -f "/data/adb/modules/\$module/disable" ] && [ -f "/data/adb/modules/\$module/sepolicy.rule" ]; then
        /sbin/magiskpolicy --live --apply "/data/adb/modules/\$module/sepolicy.rule"
    fi
done
EOF
unzip -q -o ${ROOT}/out/Magisk/app-debug.apk -d ${ROOT}/out/Magisk/app-debug.apk.unpacked
cp ${ROOT}/out/Magisk/app-debug.apk ${ROOT}/out/target/${TARGET_ARCH}/Magisk.apk
mkdir magisk
if [[ ${MAGISK_ARCH} == 'arm64-v8a' ]]
then
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/arm64-v8a/libmagisk64.so magisk/magisk64
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/armeabi-v7a/libmagisk32.so magisk/magisk32
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/arm64-v8a/libmagiskinit.so magisk/magiskinit
else
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/x86_64/libmagisk64.so magisk/magisk64
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/x86/libmagisk32.so magisk/magisk32
    cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/x86_64/libmagiskinit.so magisk/magiskinit
fi
ln -sf magiskinit magisk/magiskpolicy
cp ${ROOT}/out/Magisk/app-debug.apk.unpacked/lib/${CURRENT_ARCH}/libmagiskinit.so magiskpolicy
sudo cp magisk/* system/sbin/
sudo find system/sbin -type f -exec chmod 0755 {} \;
sudo find system/sbin -type f -exec chown root:root {} \;
sudo find system/sbin -type f -exec chcon --reference system/product {} \;
chmod +x magiskpolicy
echo '/dev/wsa-magisk(/.*)?    u:object_r:magisk_file:s0' | sudo tee -a system/vendor/etc/selinux/vendor_file_contexts
sudo ./magiskpolicy --load system/vendor/etc/selinux/precompiled_sepolicy --save system/vendor/etc/selinux/precompiled_sepolicy \
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
sudo umount system
sudo rm -rf system
rm -rf ${ROOT}/out/Magisk/app-debug.apk.unpacked
for file in system.img system_ext.img product.img vendor.img
do
    cp ${file} ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
    mv ${file}.orig ${file}
    e2fsck -yf ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
    resize2fs -M ${ROOT}/out/target/${TARGET_ARCH}/WSA-Deploy/${file}
done
# Recover backup, you can use these ${ROOT}/out/WSA-Deploy folder for installing WSA with only Kernel-assisted su 
# and deploy Magisk emulator, which is the traditional way to use Magisk on WSA.
cd ${ROOT}
info "All jobs are done, you can copy ${ROOT}/out/target/${TARGET_ARCH} to Windows and run deploy.ps1 for deploying."
