#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "usage: ./build.sh <version>"
    echo "example: ./build.sh 21.1.5"
    echo "support versions: >=17.0.0"
    exit 1
fi

# llvm 的版本。这个脚本同时支持编 llvm 17、18、19、20、21，只需要输入不同的版本号就能自动下载对应版本的源码进行编译
LLVM_VERSION=$1

# 当前工作目录。拼接绝对路径的时候需要用到这个值。
WORKDIR=$(pwd)

# llvm 安装目录
LLVM_INSTALL_DIR=${WORKDIR}/llvm-${LLVM_VERSION}-ohos-arm64

# 如果存在旧的目录和文件，就清理掉
rm -rf *.tar.gz \
    llvm-project-llvmorg-${LLVM_VERSION} \
    ohos-sdk \
    llvm-${LLVM_VERSION}-ohos-arm64

# 准备 ohos-sdk
mkdir ohos-sdk
curl -L -O https://repo.huaweicloud.com/openharmony/os/6.0-Release/ohos-sdk-windows_linux-public.tar.gz
tar -zxf ohos-sdk-windows_linux-public.tar.gz -C ohos-sdk
cd ohos-sdk/linux
unzip -q native-*.zip
cd ../..

# 准备 llvm 源码
curl -L -O https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-${LLVM_VERSION}.tar.gz
rm -rf llvmorg-${LLVM_VERSION}
tar -zxf llvmorg-${LLVM_VERSION}.tar.gz
cd llvm-project-llvmorg-${LLVM_VERSION}/

# 打补丁，这是为了让 llvm 能识别 OpenHarmony 的 libc++。
# 参考了 OpenHarmony 社区的处理方案：https://gitcode.com/openharmony/third_party_llvm-project/commit/42581c4cb83a4ef7cc2a06be92681a0cb50f4549?ref=llvm-19.1.7
patch -p1 < ../0001-adapt-to-ohos.patch

# 编译本机工具（llvm-tblgen 和 clang-tblgen）。编 llvm 的时候需要它们做代码生成。
rm -rf build-host
mkdir build-host
cd build-host
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang" \
  ../llvm
ninja llvm-tblgen clang-tblgen
cd ..

# 编译目标平台产物
# 
# 参数解释：
# 
# 构建 Release 版本
# -DCMAKE_BUILD_TYPE=Release
#
# 安装路径。这个路径仅用于打包编译产物，实际运行的时候放到哪里都可以。
# -DCMAKE_INSTALL_PREFIX="${LLVM_INSTALL_DIR}"
# 
# 交叉编译（目标平台是 Linux aarch64。llvm 眼里 ohos 是 Linux 的一个 ABI 分支，类似于 android）
#  -DCMAKE_SYSTEM_NAME=Linux
#  -DCMAKE_SYSTEM_PROCESSOR=aarch64
#  -DCMAKE_C_COMPILER=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/aarch64-unknown-linux-ohos-clang
#  -DCMAKE_CXX_COMPILER=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/aarch64-unknown-linux-ohos-clang++
# 
# 本机工具的路径
# -DLLVM_TABLEGEN=$(pwd)/../build-host/bin/llvm-tblgen
# -DCLANG_TABLEGEN=$(pwd)/../build-host/bin/clang-tblgen
# 
# 只编译目标后端。避免编译产物体积过大。
# -DLLVM_TARGET_ARCH=AArch64
# -DLLVM_TARGETS_TO_BUILD=AArch64
# -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-ohos
# 
# OpenHarmony 的 sysroot。这里硬编码成 llvm 安装目内的路径，以便将 sysroot 随编译器发布。
# 用户如果不想使用这一份 sysroot，也可以在调用编译器的时候自己指定一个 --sysroot 参数进行覆盖。
# -DDEFAULT_SYSROOT='../sysroot'
#
# rpath 用 $ORIGIN，绝对路径清零。这是为了让编译器“可重定位”，无论安装什么位置都能跑。
# -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib'
# -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
# -DCMAKE_SKIP_BUILD_RPATH=OFF
#
# 配置文件路径
# -DCLANG_CONFIG_FILE_SYSTEM_DIR='$ORIGIN/../lib/clang.cfg.d'
#
# 需要编译的子项目。这里没编运行时库，因为编运行时库会遇到很多坑。
# -DLLVM_ENABLE_PROJECTS='clang;lld;lldb'
#
# 需要 clang/lld 等可执行文件
# -DLLVM_BUILD_TOOLS=ON
# -DCLANG_BUILD_TOOLS=ON
# -DLLD_BUILD_TOOLS=ON
#
# 不要例子/文档/工具链测试
# -DLLVM_INCLUDE_EXAMPLES=OFF
# -DLLVM_INCLUDE_TESTS=OFF
# -DLLVM_INCLUDE_DOCS=OFF
# -DLLVM_INCLUDE_BENCHMARKS=OFF
# -DCLANG_INCLUDE_TESTS=OFF
#
# 不要 utils 目录里一堆小工具。如 llvm-exegesis、llvm-mca、llvm-reduce 等。
# -DLLVM_BUILD_UTILS=OFF
# 
# 只安装工具链，不安装开发态资源，节省一半体积
# -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON
#
# 自动进行 strip 以减少体积
# -DCMAKE_STRIP=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/llvm-strip
#
# 禁用 LLDB 的 libxml2 支持。
# 如果你的构建机上有这个库且你没禁用它，那在交叉编译的时候，构建系统就会拿构建机（x86_64-linux-gnu）上的 libxml2.so
# 去跟目标平台（aarch64-unknown-linux-ohos）的 .o 文件链接，导致构建失败。
# -DLLDB_ENABLE_LIBXML2=OFF
#
mkdir build-target
cd build-target
cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${LLVM_INSTALL_DIR}" \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/aarch64-unknown-linux-ohos-clang \
  -DCMAKE_CXX_COMPILER=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/aarch64-unknown-linux-ohos-clang++ \
  -DLLVM_TABLEGEN=$(pwd)/../build-host/bin/llvm-tblgen \
  -DCLANG_TABLEGEN=$(pwd)/../build-host/bin/clang-tblgen \
  -DLLVM_TARGET_ARCH=AArch64 \
  -DLLVM_TARGETS_TO_BUILD=AArch64 \
  -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-ohos \
  -DDEFAULT_SYSROOT='../sysroot' \
  -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_SKIP_BUILD_RPATH=OFF \
  -DCLANG_CONFIG_FILE_SYSTEM_DIR='$ORIGIN/../lib/clang.cfg.d' \
  -DLLVM_ENABLE_PROJECTS='clang;lld;lldb' \
  -DLLVM_BUILD_TOOLS=ON \
  -DCLANG_BUILD_TOOLS=ON \
  -DLLD_BUILD_TOOLS=ON \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON \
  -DCMAKE_STRIP=${WORKDIR}/ohos-sdk/linux/native/llvm/bin/llvm-strip \
  -DLLDB_ENABLE_LIBXML2=OFF \
  ../llvm
ninja install
cd ../..

# 从 sdk 里面把运行时库拷贝到产物中（我们没有自己编运行时库，而是从 sdk 里面拷）
LLVM_SHORT_VERSION=$(echo ${LLVM_VERSION} | cut -d'.' -f1)
mkdir -p ${LLVM_INSTALL_DIR}/lib/clang/${LLVM_SHORT_VERSION}/lib/aarch64-linux-ohos
cp -r ohos-sdk/linux/native/llvm/include/c++ ${LLVM_INSTALL_DIR}/include/c++
cp -r ohos-sdk/linux/native/llvm/include/libcxx-ohos ${LLVM_INSTALL_DIR}/include/libcxx-ohos
cp -r ohos-sdk/linux/native/llvm/lib/clang/15.0.4/lib/aarch64-linux-ohos/* ${LLVM_INSTALL_DIR}/lib/clang/${LLVM_SHORT_VERSION}/lib/aarch64-linux-ohos/
cp -r ohos-sdk/linux/native/llvm/lib/aarch64-linux-ohos/* ${LLVM_INSTALL_DIR}/lib/clang/${LLVM_SHORT_VERSION}/lib/aarch64-linux-ohos/

# 从 sdk 里面把 sysroot 拷贝到产物中
cp -r ohos-sdk/linux/native/sysroot ${LLVM_INSTALL_DIR}/sysroot

# 履行开源义务，将 license 随制品一起发布
cp llvm-project-llvmorg-${LLVM_VERSION}/LICENSE.TXT ${LLVM_INSTALL_DIR}/NOTICE.llvm.txt
printf '%s\n' "$(cat <<EOF
The following directories are copied from ohos-sdk, which is part of the OpenHarmony project:
- include/c++
- include/libcxx-ohos
- lib/clang/${LLVM_SHORT_VERSION}/lib/aarch64-linux-ohos
- sysroot

The download address for the ohos-sdk artifacts and the full source code of the OpenHarmony project
can be obtained on this page:

https://gitee.com/openharmony/docs/blob/master/en/release-notes/OpenHarmony-v6.0-release.md

The copyright of these directories belongs to the OpenHarmony project. These directories are licensed
under the same terms as the OpenHarmony project, which can be found at: 

https://gitcode.com/openharmony/docs/blob/master/en/contribute/open-source-software-and-license-notice.md
EOF
)" > ${LLVM_INSTALL_DIR}/NOTICE.ohos-sdk.txt

# 打包最终产物
tar -zcf llvm-${LLVM_VERSION}-ohos-arm64.tar.gz llvm-${LLVM_VERSION}-ohos-arm64
