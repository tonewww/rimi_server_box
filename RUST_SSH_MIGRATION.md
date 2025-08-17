# SSH2-RS FFI Migration Plan

## Overview
Migrate from Dart's `dartssh2` to Rust's `ssh2-rs` library using FFI (Foreign Function Interface) for better performance and native SSH capabilities.

## Architecture Design

### Current Architecture
```
Flutter/Dart App
    ↓
dartssh2 (Pure Dart)
    ↓
Native SSH Libraries
```

### Target Architecture
```
Flutter/Dart App
    ↓
Dart FFI Bindings
    ↓
Rust SSH Library (ssh2-rs)
    ↓
Native libssh2
```

## Implementation Phases

### Phase 1: Rust Library Setup
1. Create Rust library project
2. Add ssh2-rs dependencies
3. Define C-compatible API
4. Implement core SSH functions
5. Build dynamic library (.dylib, .so, .dll)

### Phase 2: Dart FFI Bindings
1. Generate Dart FFI bindings
2. Create Dart wrapper classes
3. Implement memory management
4. Handle async operations
5. Error handling and type conversion

### Phase 3: Integration
1. Replace dartssh2 calls with FFI calls
2. Update existing SSH client extensions
3. Maintain API compatibility where possible
4. Performance optimization

### Phase 4: Testing & Validation
1. Unit tests for Rust library
2. Integration tests for FFI bindings
3. End-to-end testing
4. Performance benchmarks

## Technical Requirements

### Rust Library Features Needed
- SSH connection management
- Authentication (password, key-based, keyboard-interactive)
- Command execution
- SFTP operations
- Port forwarding
- Session management

### FFI Considerations
- Memory safety between Dart and Rust
- Async operation handling
- Error propagation
- String encoding (UTF-8)
- Callback mechanisms for streams

### Build System Integration
- Cross-platform compilation
- Flutter build integration
- Native library packaging
- Platform-specific optimizations

## Benefits
1. **Performance**: Native Rust performance vs Dart interpretation
2. **Memory**: Better memory management and reduced GC pressure
3. **Features**: Access to full libssh2 feature set
4. **Maintenance**: Leverage mature ssh2-rs ecosystem
5. **Security**: Rust's memory safety guarantees

## Challenges
1. **Complexity**: FFI adds complexity vs pure Dart
2. **Build System**: Need to compile Rust for all target platforms
3. **Debugging**: Cross-language debugging is harder
4. **Distribution**: Need to package native libraries
5. **Async**: Complex async bridging between Dart and Rust

## File Structure
```
rimi_server_box/
├── rust_ssh/              # Rust SSH library
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs
│   │   ├── ssh.rs
│   │   ├── sftp.rs
│   │   └── ffi.rs
│   └── build.rs
├── lib/
│   ├── ffi/               # Dart FFI bindings
│   │   ├── ssh_bindings.dart
│   │   └── ssh_client.dart
│   └── core/
│       └── ssh/           # Updated SSH client
└── native/               # Compiled libraries
    ├── linux/
    ├── macos/
    ├── windows/
    └── android/
```

## Development Plan
1. **Week 1**: Rust library foundation
2. **Week 2**: Core SSH functionality
3. **Week 3**: FFI bindings and Dart integration
4. **Week 4**: SFTP and advanced features
5. **Week 5**: Testing and optimization
6. **Week 6**: Documentation and cleanup

## Success Criteria
- All existing SSH functionality preserved
- Performance improvement over dartssh2
- Successful builds on all target platforms
- All tests passing
- Memory safety and stability
- Maintainable codebase