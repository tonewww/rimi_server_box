# SSH 连接交互流程时序图

## 完整流程时序图

```mermaid
sequenceDiagram
    participant User as 用户界面
    participant SSHPage as SSH页面
    participant Terminal as Terminal组件
    participant GenClient as genClient函数
    participant SSHSocket as SSHSocket
    participant SSHClient as SSHClient
    participant SSHSession as SSHSession
    participant Server as SSH服务器
    participant SessionMgr as 会话管理器

    %% 初始化阶段
    User->>SSHPage: 点击连接SSH
    SSHPage->>SSHPage: initState()
    SSHPage->>SessionMgr: add(sessionId, status:connecting)
    SSHPage->>Terminal: 创建Terminal实例
    SSHPage->>SSHPage: afterFirstLayout() 
    SSHPage->>SSHPage: _initTerminal()
    
    %% 连接建立阶段
    SSHPage->>Terminal: writeLn("等待连接...")
    SSHPage->>GenClient: genClient(spi, onStatus)
    
    GenClient->>GenClient: 检查跳板服务器
    alt 有跳板服务器
        GenClient->>GenClient: 递归调用genClient(jumpSpi)
        GenClient->>SSHSocket: forwardLocal(ip, port)
    else 直连
        GenClient->>SSHSocket: connect(ip, port, timeout)
    end
    
    SSHSocket->>Server: TCP连接
    Server-->>SSHSocket: TCP连接成功
    
    GenClient->>SSHClient: new SSHClient(socket, username)
    
    alt 密钥认证
        GenClient->>GenClient: loadIdentity(privateKey)
        GenClient->>SSHClient: 设置identities
    else 密码认证
        GenClient->>SSHClient: 设置onPasswordRequest
    end
    
    SSHClient->>Server: SSH握手
    Server-->>SSHClient: SSH握手成功
    
    SSHClient->>Server: 用户认证
    Server-->>SSHClient: 认证成功
    
    GenClient-->>SSHPage: 返回SSHClient实例
    
    %% Shell会话建立
    SSHPage->>Terminal: writeLn("执行: Shell")
    SSHPage->>SSHClient: shell(pty, environment)
    
    SSHClient->>SSHSession: 创建Session
    SSHSession->>Server: 请求PTY
    Server-->>SSHSession: PTY分配成功
    SSHSession->>Server: 请求Shell
    Server-->>SSHSession: Shell启动
    
    SSHClient-->>SSHPage: 返回SSHSession
    SSHPage->>SessionMgr: updateStatus(sessionId, connected)
    
    %% 数据流绑定
    SSHPage->>Terminal: 清空缓冲区
    SSHPage->>Terminal: 设置onOutput回调
    SSHPage->>Terminal: 设置onResize回调
    SSHPage->>SSHSession: 监听stdout
    SSHPage->>SSHSession: 监听stderr
    
    %% 交互阶段
    loop 用户交互
        User->>Terminal: 输入命令
        Terminal->>Terminal: onOutput(data)
        Terminal->>SSHSession: write(utf8.encode(data))
        SSHSession->>Server: 发送数据
        
        Server->>Server: 执行命令
        Server-->>SSHSession: 返回输出(stdout/stderr)
        
        alt stdout数据
            SSHSession-->>Terminal: stdout.stream
            Terminal->>Terminal: write(data)
            Terminal->>User: 显示输出
        else stderr数据
            SSHSession-->>Terminal: stderr.stream  
            Terminal->>Terminal: write(data)
            Terminal->>User: 显示错误
        end
    end
    
    %% 窗口调整
    opt 窗口大小变化
        User->>Terminal: 调整窗口
        Terminal->>Terminal: onResize(width, height)
        Terminal->>SSHSession: resizeTerminal(width, height)
        SSHSession->>Server: 更新PTY大小
    end
    
    %% 保活机制
    loop 每5秒
        SSHPage->>SSHClient: ping()
        SSHClient->>Server: 发送保活包
        alt 成功
            Server-->>SSHClient: 响应
        else 超时/失败
            SSHPage->>Terminal: writeLn("Connection lost")
            SSHPage->>SessionMgr: updateStatus(disconnected)
            SSHPage->>User: 显示断开对话框
        end
    end
    
    %% 断开连接
    opt 用户主动断开
        User->>SSHPage: 关闭页面
        SSHPage->>SSHSession: close()
        SSHSession->>Server: 关闭连接
        SSHPage->>SessionMgr: remove(sessionId)
        SSHPage->>SSHPage: dispose()
    end
```

## 核心组件职责

### 1. **SSHPage** (`lib/view/page/ssh/page/page.dart`)
- 管理SSH连接生命周期
- 处理UI交互
- 管理Terminal组件
- 维护会话状态

### 2. **Terminal** (xterm库)
- 终端显示和渲染
- 处理用户输入
- 管理终端缓冲区
- 支持ANSI转义序列

### 3. **genClient** (`lib/core/utils/server.dart`)
- 创建SSH客户端
- 处理认证逻辑
- 支持跳板服务器
- 管理连接超时

### 4. **SSHClient** (dartssh2库)
- SSH协议实现
- 会话管理
- 数据加密传输
- 认证处理

### 5. **SSHSession** (dartssh2库)
- 管理单个SSH会话
- 处理stdin/stdout/stderr流
- PTY管理
- 命令执行

### 6. **TermSessionManager** (`lib/data/ssh/session_manager.dart`)
- 跟踪活跃SSH会话
- Android前台服务通知
- iOS Live Activities
- 会话状态同步

## 关键流程说明

### 连接建立流程
1. 用户点击连接，创建`SSHPage`实例
2. 调用`genClient`创建SSH客户端
3. 建立TCP连接（直连或通过跳板）
4. SSH协议握手
5. 用户认证（密钥/密码/交互式）
6. 创建Shell会话

### 数据流转机制
```
用户输入 → Terminal.onOutput → SSHSession.write → SSH服务器
SSH服务器 → SSHSession.stdout/stderr → Terminal.write → 屏幕显示
```

### 保活机制
- 每5秒发送ping命令
- 3秒超时检测
- 失败时更新会话状态并提示用户

### 断开处理
- 正常断开：清理资源，移除会话记录
- 异常断开：显示重连对话框，更新会话状态
- 资源清理：关闭连接，释放内存，停止定时器