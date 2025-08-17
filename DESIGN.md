# SSH Library Migration Design Document

## Executive Summary
This document outlines the design for migrating from `dartssh2` to an alternative Dart SSH library in the ServerBox Flutter application.

## Alternative Library Analysis

### Option 1: ssh2 (pub.dev)
- **Package**: `ssh2`
- **Status**: Available on pub.dev
- **Pros**: Official pub.dev package, potentially more stable
- **Cons**: Need to verify feature completeness

### Option 2: dartssh (GreenAppers)
- **Package**: `dartssh`
- **Repository**: https://github.com/GreenAppers/dartssh
- **Pros**: Pure Dart implementation with tunneling support
- **Cons**: Less actively maintained than dartssh2

### Option 3: Stay with dartssh2 but migrate to pub.dev version
- **Package**: `dartssh2`
- **Current**: Git dependency (v1.0.285)
- **Alternative**: Official pub.dev version
- **Pros**: Minimal code changes, same API
- **Cons**: May not address the core migration requirement

## Recommended Approach: Migrate to pub.dev dartssh2

Based on analysis, the recommended approach is to migrate from the git-based `dartssh2` to the official pub.dev version of `dartssh2`. This provides:
- Minimal code changes
- Better dependency management
- More stable releases
- Same feature set

## Architecture Design

### Current Architecture
```
Flutter App
    ↓
dartssh2 (git dependency)
    ↓
SSH Server Connection
```

### Target Architecture
```
Flutter App
    ↓
dartssh2 (pub.dev dependency)
    ↓
SSH Server Connection
```

## Migration Strategy

### Phase 1: Dependency Migration
1. Update `pubspec.yaml` to use pub.dev version
2. Verify API compatibility
3. Update import statements if needed

### Phase 2: Code Validation
1. Test all SSH functionality
2. Verify SFTP operations
3. Check error handling
4. Validate jump server functionality

### Phase 3: Testing & Validation
1. Unit tests for SSH operations
2. Integration tests with real servers
3. Performance testing
4. Platform compatibility testing

## Implementation Details

### Files to Modify

#### Primary SSH Implementation Files
1. `lib/core/extension/ssh_client.dart`
   - SSH client extensions
   - Command execution methods
   - PowerShell session handling

2. `lib/core/utils/server.dart`
   - SSH client generation
   - Authentication handling
   - Key management

3. `lib/data/model/sftp/worker.dart`
   - SFTP operations
   - File transfer logic

#### Secondary Files (Import Updates)
- `lib/view/page/storage/sftp.dart`
- `lib/view/page/ssh/page/page.dart`
- `lib/view/page/process.dart`
- `lib/data/provider/server.dart`
- `lib/data/provider/pve.dart`
- `lib/data/provider/container.dart`
- And other files using SSH functionality

### API Compatibility Analysis

#### Current API Usage Patterns
```dart
// SSH Client Creation
SSHClient(socket, username: user, onPasswordRequest: () => pwd)

// Command Execution
final session = await client.execute(command, pty: pty, environment: env)

// Stream Handling
session.stdout.listen((e) => onStdout?.call(e.string, session))
session.stderr.listen((e) => onStderr?.call(e.string, session))

// Key Loading
SSHKeyPair.fromPem(key)
SSHKeyPair.isEncryptedPem(key)
```

#### Migration Validation Points
- Verify all these APIs exist in target library
- Check for any breaking changes
- Validate parameter compatibility
- Ensure stream handling works identically

## Risk Assessment

### Low Risk
- API compatibility (likely identical for pub.dev dartssh2)
- Basic SSH operations
- Authentication methods

### Medium Risk
- Version differences between git and pub.dev versions
- Build system integration
- Platform-specific implementations

### High Risk
- Breaking changes in newer versions
- Performance regressions
- Dependency conflicts

## Rollback Strategy
1. Keep git-based dependency as backup in comments
2. Create feature branch for migration
3. Comprehensive testing before merge
4. Ability to quickly revert pubspec.yaml changes

## Testing Strategy

### Unit Tests
- SSH connection establishment
- Authentication methods
- Command execution
- Error handling

### Integration Tests
- Real server connections
- File transfer operations
- Jump server functionality
- Cross-platform compatibility

### Performance Tests
- Connection speed benchmarks
- Memory usage monitoring
- Battery usage on mobile devices

## Success Metrics
1. All existing functionality preserved
2. No performance degradation
3. Successful build on all platforms
4. All tests passing
5. Dependency management improved