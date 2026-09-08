# ist-Open-Box

将 [liandu2024/Open-Box](https://github.com/liandu2024/Open-Box) 最新正式 Release 自动封装为适用于 **iStoreOS / OpenWrt x86_64** 的标准 IPK。

本仓库不是 Open-Box 的 Fork，也不长期复制上游源码。GitHub Actions 只下载上游正式 Release 中已经构建好的自包含 x64 资产，校验官方 SHA256 后重新封装。

## 自动构建

工作流支持：

- 在 GitHub Actions 页面手动运行；
- 每天北京时间 02:20 自动检查上游最新正式版本；
- 已发布过同一上游版本时自动跳过；
- 手动运行时可选择 `force_rebuild` 强制重建；
- 同时保存 Actions Artifact，并发布到本仓库 Releases。

## 安装

下载 Release 中的 `open-box_<版本>-1_x86_64.ipk`，然后通过 iStoreOS 软件包页面上传安装，或通过 SSH 执行：

```sh
opkg install ./open-box_*_x86_64.ipk
```

安装后会：

- 部署 Open-Box 到 `/opt/open-box/`；
- 安装 OpenWrt init.d 服务与 LuCI 兜底页面；
- 创建并保留 `/opt/open-box/data/`；
- 启用并启动面板服务；
- 不自动启动代理内核，首次进入面板完成配置后再启动。

面板通常位于：

```text
http://路由器局域网IP:2026
```

## 升级与卸载

- IPK 升级不会打包或覆盖 `/opt/open-box/data/`；
- 卸载时默认保留 `/opt/open-box/data/`；
- 如需彻底删除用户数据，请在确认不再需要配置后手动删除该目录。

## 本地测试

```sh
chmod +x scripts/build-ipk.sh tests/test-build-ipk.sh
./tests/test-build-ipk.sh
```

## 说明

Open-Box 及其组件版权、许可证和安全说明以[上游项目](https://github.com/liandu2024/Open-Box)为准。本仓库仅提供自动化封装流程。
