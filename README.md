# ohos-llvm

本项目为 OpenHarmony 平台编译了 LLVM，并发布预构建包。

## 获取预构建包

前往 [release 页面](https://github.com/Harmonybrew/ohos-llvm/releases) 获取。

## 用法

**1\. 在鸿蒙 PC 中使用**

因系统安全规格限制等原因，暂不支持通过“解压 + 配 PATH” 的方式使用这个软件包。

你可以尝试将 tar 包打成 hnp 包再使用，详情请参考 [DevBox](https://gitcode.com/OpenHarmonyPCDeveloper/devbox) 的方案。

**2\. 在鸿蒙开发板中使用**

用 hdc 把它推到设备上，然后以“解压 + 配 PATH” 的方式使用。

示例：
```sh
hdc file send llvm-21.1.5-ohos-arm64.tar.gz /data
hdc shell

cd /data
tar -zxf llvm-21.1.5-ohos-arm64.tar.gz
export PATH=$PATH:/data/llvm-21.1.5-ohos-arm64/bin

# 现在可以使用 clang 命令了
```

**3\. 在 [鸿蒙容器](https://github.com/hqzing/docker-mini-openharmony) 中使用**

在容器中用 curl 下载这个软件包，然后以“解压 + 配 PATH” 的方式使用。

示例：
```sh
docker run -itd --name=ohos ghcr.io/hqzing/docker-mini-openharmony:latest
docker exec -it ohos sh

cd /root
curl -L -O https://github.com/Harmonybrew/ohos-llvm/releases/download/20251121/llvm-21.1.5-ohos-arm64.tar.gz
tar -zxf llvm-21.1.5-ohos-arm64.tar.gz -C /opt
export PATH=$PATH:/opt/llvm-21.1.5-ohos-arm64/bin

# 现在可以使用 clang 命令了
```

## 从源码构建

**1\. 手动构建**

需要用一台 Linux x64 服务器来运行项目里的 build.sh，以实现 LLVM 的交叉编译。

这里以 Ubuntu 24.04 x64 作为示例：
```sh
sudo apt update && sudo apt install -y build-essential unzip cmake ninja-build python3
./build.sh 21.1.5

```

**2\. 使用流水线构建**

如果你熟悉 GitHub Actions，你可以直接复用项目内的工作流配置，使用 GitHub 的流水线来完成构建。

这种情况下，你使用的是 GitHub 提供的构建机，不需要自己准备构建环境。

只需要这么做，你就可以进行你的个人构建：
1. Fork 本项目，生成个人仓
2. 在个人仓的“Actions”菜单里面启用工作流
3. 在个人仓提交代码或发版本，触发流水线运行

## 常见问题

**1\. 编译器不能正常使用**

本项目提供的 LLVM 直接构建自 LLVM 官方上游代码，并不是由 OpenHarmony 社区维护的 [fork 版本](https://gitcode.com/openharmony/third_party_llvm-project)。

由于 OpenHarmony 的大量平台适配尚未合入上游，本项目提供的 LLVM 对 OpenHarmony 的原生支持程度远不及 ohos-sdk 官方工具链。在深度使用场景下，可能会遇到构建失败或隐性兼容性故障。

举个例子：虽然本项目发布了 LLVM 21 的制品，但是它里面的 libc++ 还是 LLVM 15 的 libc++，因为它的运行时库（包含 libc++）是从 ohos-sdk 6.0 （LLVM 15）复制过来的。如果你的 C++ 代码中使用到类似 `std::ranges` 之类的新特性，用这个 LLVM 21 去编译它一定会失败。

对稳定性及特性完整性有较高要求的项目，请优先使用 ohos-sdk 提供的 LLVM 工具链。
