# Current dartssh2 Implementation Analysis Report

## Files Using SSH Functionality

### Core SSH Implementation
1. **lib/core/extension/ssh_client.dart** - SSH client extensions and command execution
2. **lib/core/utils/server.dart** - SSH client generation and key management
3. **lib/core/extension/sftpfile.dart** - SFTP file permissions and Unix mode conversion

### Data Models
4. **lib/data/model/sftp/worker.dart** - SFTP file transfer operations in isolates
5. **lib/data/model/sftp/browser_status.dart** - SFTP browser state management
6. **lib/data/model/server/server.dart** - Server model with SSH client

### Data Providers
7. **lib/data/provider/server.dart** - Server data provider
8. **lib/data/provider/pve.dart** - Proxmox VE provider using SSH
9. **lib/data/provider/container.dart** - Container management provider

### UI Components
10. **lib/view/page/storage/sftp.dart** - SFTP file browser UI
11. **lib/view/page/ssh/page/page.dart** - SSH terminal UI
12. **lib/view/page/process.dart** - Process management UI
13. **lib/view/page/private_key/edit.dart** - Private key editing

### Helpers
14. **lib/data/helper/system_detector.dart** - System type detection via SSH

## API Usage Patterns

### SSH Client Creation and Management
- **SSHClient** constructor with socket, username, password/key authentication
- **SSHSocket.connect()** for establishing connections
- **genClient()** utility function with timeout, jump server, and authentication support

### SSH Key Management
- **SSHKeyPair.fromPem()** for loading keys from PEM format
- **SSHKeyPair.isEncryptedPem()** for checking encryption
- **loadIdentity()** function for multi-threaded key loading

### SSH Command Execution
- **SSHClient.execute()** for command execution
- **SSHSession** for managing command sessions
- Custom extensions: **execPowerShell()**, **exec()**, **execWithPwd()**
- Stream handling for stdout/stderr with **session.stdout.listen()**

### SFTP Operations
- **client.sftp()** for SFTP client creation
- **SftpClient** for file operations
- **sftp.open()** with various **SftpFileOpenMode** flags
- **file.read()** and **file.write()** for data transfer
- **SftpFileMode** extensions for Unix permissions

### Authentication Methods
- Password authentication: **onPasswordRequest**
- Key-based authentication: **identities** parameter
- Keyboard-interactive: **onUserInfoRequest**

## Custom Configurations and Features

### Jump Server Support
- Proxy/jump server functionality via **jumpSpi** parameter
- **client.forwardLocal()** for port forwarding

### PowerShell Integration
- Custom **execPowerShell()** method for Windows servers
- Non-interactive PowerShell execution with bypass policy

### Multi-threading Support
- SFTP operations run in isolates using **easy_isolate**
- Thread-safe key loading with **compute()** function

### Error Handling
- Custom error types and exception handling
- Timeout management for connections
- Password prompt handling for sudo operations

### Platform-specific Features
- System type detection (Windows, Linux, etc.)
- Platform-specific command execution paths

## Dependencies on dartssh2 Specific Features

### Core Classes Used
- **SSHClient**, **SSHSession**, **SSHSocket**
- **SSHKeyPair**, **SftpClient**, **SftpFileMode**
- **SSHPtyConfig**, **SftpFileOpenMode**

### Extension Methods
- Custom extensions on **SSHClient** for PowerShell and command execution
- **SftpFileMode** extensions for Unix permission conversion

### Enum Values
- **SftpFileOpenMode** flags (truncate, create, write)
- **GenSSHClientStatus** custom enum

## Migration Compatibility Requirements

### Must Preserve
1. All authentication methods (password, key, keyboard-interactive)
2. Jump server/proxy functionality
3. SFTP file operations with progress tracking
4. PowerShell session support
5. Multi-threaded operations
6. Stream-based stdout/stderr handling
7. Unix permission handling
8. Timeout and error handling mechanisms

### API Compatibility Checklist
- [ ] SSHClient constructor parameters
- [ ] SSHSocket.connect() method signature
- [ ] SSHKeyPair.fromPem() and isEncryptedPem()
- [ ] SFTP client creation and file operations
- [ ] Session execution and stream handling
- [ ] SftpFileOpenMode enum values
- [ ] SftpFileMode permission methods

## Risk Assessment

### Low Risk
- Basic SSH connection and authentication
- Standard SFTP operations
- Stream handling patterns

### Medium Risk
- Custom extension methods compatibility
- Multi-threading with isolates
- Jump server implementation details

### High Risk
- PowerShell-specific functionality
- Custom error handling patterns
- Platform-specific implementations
- Performance-critical SFTP chunking logic