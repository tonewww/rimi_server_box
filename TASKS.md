# SSH Library Migration Task Breakdown

## Task Overview
Migrate from git-based `dartssh2` dependency to pub.dev `dartssh2` package.

## Phase 1: Preparation & Analysis

### Task 1.1: Current Implementation Analysis
**Status**: Pending  
**Estimated Time**: 2 hours  
**Dependencies**: None  
**Description**: Analyze current dartssh2 usage patterns across the codebase

**Subtasks**:
- [ ] Review all imports of dartssh2
- [ ] Document API usage patterns
- [ ] Identify custom configurations
- [ ] List all SSH features currently used
- [ ] Check for any dartssh2-specific workarounds

**Deliverables**:
- Current usage analysis report
- List of all files using SSH functionality
- API compatibility requirements

### Task 1.2: Target Library Research
**Status**: Completed  
**Estimated Time**: 1 hour  
**Dependencies**: None  
**Description**: Research pub.dev dartssh2 package details

**Subtasks**:
- [x] Check pub.dev dartssh2 version availability
- [x] Compare API documentation
- [x] Review changelog for breaking changes
- [x] Verify platform support

**Deliverables**:
- Library comparison report
- Version compatibility matrix

## Phase 2: Dependency Migration

### Task 2.1: Update pubspec.yaml
**Status**: Pending  
**Estimated Time**: 30 minutes  
**Dependencies**: Task 1.1, Task 1.2  
**Description**: Update dependency from git to pub.dev version

**Subtasks**:
- [ ] Remove git-based dartssh2 dependency
- [ ] Add pub.dev dartssh2 dependency
- [ ] Run `flutter pub get`
- [ ] Verify dependency resolution
- [ ] Check for version conflicts

**Deliverables**:
- Updated pubspec.yaml
- Successful dependency resolution

### Task 2.2: Verify Build System
**Status**: Pending  
**Estimated Time**: 1 hour  
**Dependencies**: Task 2.1  
**Description**: Ensure project builds successfully with new dependency

**Subtasks**:
- [ ] Run `flutter clean`
- [ ] Run `flutter pub get`
- [ ] Attempt build for all target platforms
- [ ] Resolve any build errors
- [ ] Verify import resolution

**Deliverables**:
- Successful builds on all platforms
- Build error resolution documentation

## Phase 3: Code Migration

### Task 3.1: Update Core SSH Client Extension
**Status**: Pending  
**Estimated Time**: 2 hours  
**Dependencies**: Task 2.2  
**Description**: Update lib/core/extension/ssh_client.dart

**Subtasks**:
- [ ] Update import statements
- [ ] Verify API compatibility for SSHClient methods
- [ ] Test execPowerShell method
- [ ] Test exec method with all parameters
- [ ] Test execWithPwd method
- [ ] Verify stream handling (stdout/stderr)

**Deliverables**:
- Updated ssh_client.dart
- Verified method compatibility

### Task 3.2: Update Server Utilities
**Status**: Pending  
**Estimated Time**: 2 hours  
**Dependencies**: Task 2.2  
**Description**: Update lib/core/utils/server.dart

**Subtasks**:
- [ ] Update import statements
- [ ] Verify loadIdentity function
- [ ] Test decryptPem function
- [ ] Verify genClient function
- [ ] Test SSHKeyPair.fromPem compatibility
- [ ] Test SSHSocket.connect functionality

**Deliverables**:
- Updated server.dart
- Verified utility functions

### Task 3.3: Update SFTP Worker
**Status**: Pending  
**Estimated Time**: 1.5 hours  
**Dependencies**: Task 2.2  
**Description**: Update lib/data/model/sftp/worker.dart

**Subtasks**:
- [ ] Update import statements
- [ ] Verify SFTP functionality
- [ ] Test file operations
- [ ] Verify error handling

**Deliverables**:
- Updated sftp/worker.dart
- Verified SFTP operations

### Task 3.4: Update Provider Files
**Status**: Pending  
**Estimated Time**: 2 hours  
**Dependencies**: Task 3.1, Task 3.2  
**Description**: Update all provider files using SSH

**Subtasks**:
- [ ] Update lib/data/provider/server.dart
- [ ] Update lib/data/provider/pve.dart
- [ ] Update lib/data/provider/container.dart
- [ ] Verify SSH integration in providers

**Deliverables**:
- Updated provider files
- Verified provider functionality

### Task 3.5: Update UI Components
**Status**: Pending  
**Estimated Time**: 1.5 hours  
**Dependencies**: Task 3.1, Task 3.2  
**Description**: Update UI files that import or use SSH functionality

**Subtasks**:
- [ ] Update lib/view/page/storage/sftp.dart
- [ ] Update lib/view/page/ssh/page/page.dart
- [ ] Update lib/view/page/process.dart
- [ ] Update lib/view/page/private_key/edit.dart
- [ ] Verify UI functionality

**Deliverables**:
- Updated UI files
- Verified UI functionality

## Phase 4: Testing & Validation

### Task 4.1: Unit Testing
**Status**: Pending  
**Estimated Time**: 3 hours  
**Dependencies**: Phase 3 completion  
**Description**: Create and run unit tests for SSH functionality

**Subtasks**:
- [ ] Create tests for SSH client extensions
- [ ] Create tests for server utilities
- [ ] Create tests for SFTP operations
- [ ] Run all existing tests
- [ ] Fix any test failures

**Deliverables**:
- Comprehensive unit test suite
- All tests passing

### Task 4.2: Integration Testing
**Status**: Pending  
**Estimated Time**: 4 hours  
**Dependencies**: Task 4.1  
**Description**: Test with real SSH servers

**Subtasks**:
- [ ] Test password authentication
- [ ] Test key-based authentication
- [ ] Test keyboard-interactive authentication
- [ ] Test jump server functionality
- [ ] Test SFTP file operations
- [ ] Test PowerShell sessions
- [ ] Test error scenarios

**Deliverables**:
- Integration test results
- Performance benchmarks

### Task 4.3: Platform Testing
**Status**: Pending  
**Estimated Time**: 2 hours  
**Dependencies**: Task 4.2  
**Description**: Test on all supported platforms

**Subtasks**:
- [ ] Test on Android
- [ ] Test on iOS
- [ ] Test on Desktop platforms
- [ ] Verify platform-specific functionality

**Deliverables**:
- Platform compatibility report
- Platform-specific issue resolutions

## Phase 5: Documentation & Cleanup

### Task 5.1: Update Documentation
**Status**: Pending  
**Estimated Time**: 1 hour  
**Dependencies**: Phase 4 completion  
**Description**: Update project documentation

**Subtasks**:
- [ ] Update README if needed
- [ ] Update dependency documentation
- [ ] Document any API changes
- [ ] Update migration notes

**Deliverables**:
- Updated documentation
- Migration completion report

### Task 5.2: Code Review & Cleanup
**Status**: Pending  
**Estimated Time**: 1 hour  
**Dependencies**: Task 5.1  
**Description**: Final code review and cleanup

**Subtasks**:
- [ ] Remove any temporary code
- [ ] Clean up comments
- [ ] Verify code style consistency
- [ ] Final build verification

**Deliverables**:
- Clean, production-ready code
- Final build success confirmation

## Risk Mitigation Tasks

### Risk Task R1: Backup Strategy
**Status**: Pending  
**Priority**: High  
**Description**: Create rollback plan

**Subtasks**:
- [ ] Create feature branch for migration
- [ ] Document current working state
- [ ] Keep git dependency as fallback option
- [ ] Create rollback procedure

### Risk Task R2: Performance Validation
**Status**: Pending  
**Priority**: Medium  
**Description**: Ensure no performance regression

**Subtasks**:
- [ ] Measure current performance baselines
- [ ] Compare performance after migration
- [ ] Profile memory usage
- [ ] Monitor connection speed

## Success Criteria Checklist
- [ ] All builds successful on target platforms
- [ ] All existing functionality preserved
- [ ] All tests passing
- [ ] No performance regression
- [ ] Documentation updated
- [ ] Migration completed without user-facing changes

## Estimated Total Time: 20-25 hours
## Target Completion: To be determined based on development schedule