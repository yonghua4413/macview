# MacView - 远程控制 Mac 应用规格

## 1. 项目概述

- **项目名称**: MacView
- **Mac 端**: mac-server (VNC 服务器)
- **iOS 端**: ios-client (VNC 客户端)
- **核心功能**: iPhone 横屏显示 Mac 画面，支持点击、输入文字进行远程控制
- **目标平台**: macOS 12+, iOS 15+
- **网络**: 局域网

## 2. 技术方案

### 协议层
- **VNC (RFB - Remote Framebuffer)**: 标准的远程帧缓冲协议
- **帧编码**: 主要使用 Raw 编码，Zlib 压缩编码作为补充

### Mac 端实现
- **屏幕捕获**: CGDisplayStream API (高效屏幕录制)
- **VNC 服务器**: 监听 5900 端口，RFB 协议实现
- **鼠标控制**: CGEvent API 模拟鼠标事件
- **键盘控制**: CGEvent API 模拟键盘事件

### iOS 端实现
- **UI 框架**: SwiftUI
- **网络**: Network.framework (NWConnection)
- **渲染**: Core Graphics + CALayer
- **控制**: UITouch 事件转换为 VNC 鼠标事件

## 3. UI/UX

### iOS 端
- **主界面**: 横屏全屏显示 Mac 画面
- **连接状态**: 顶部状态栏显示连接状态
- **连接流程**: 启动时扫描局域网 VNC 服务器，或手动输入 IP

### Mac 端
- **菜单栏**: 显示连接状态，连接客户端数量
- **托盘菜单**: 退出服务器选项

## 4. 功能

### 核心功能
1. Mac 屏幕实时推流到 iPhone
2. iPhone 点击对应 Mac 鼠标点击
3. iPhone 长按对应 Mac 右键
4. iPhone 滑动对应 Mac 鼠标移动
5. iPhone 键盘输入对应 Mac 键盘输入
6. 支持屏幕缩放和拖拽

### 连接流程
1. Mac 端启动 VNC 服务器 (端口 5900)
2. iOS 端连接 Mac 的 IP:5900
3. 进行 VNC handshake
4. 开始屏幕推流和控制

## 5. 项目结构

```
macview/
├── SPEC.md
├── mac-server/          # Mac VNC 服务器
│   ├── Sources/
│   │   └── Server/
│   │       ├── main.swift
│   │       ├── VNCServer.swift
│   │       ├── ScreenCapture.swift
│   │       └── InputSimulator.swift
│   └── project.yml
└── ios-client/          # iOS VNC 客户端
    ├── Sources/
    │   └── Client/
    │       ├── App/
    │       │   └── MacViewApp.swift
    │       ├── Views/
    │       │   ├── ContentView.swift
    │       │   └── RemoteScreenView.swift
    │       ├── ViewModels/
    │       │   └── VNCViewModel.swift
    │       ├── Models/
    │       │   └── VNCProtocol.swift
    │       └── Network/
    │           └── VNCConnection.swift
    └── project.yml
```
