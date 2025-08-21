# CI Workflow Consolidation

This document explains the consolidation of GitHub Actions workflows to eliminate redundancy and improve CI efficiency.

## Problem
Previously, we had **7 different workflow files** running on every push/PR:

1. `ci.yaml` - Docker build & self-check 
2. `ci.yml` - Node.js/pnpm build & ASCII checks
3. `codespell.yml` - Spell checking
4. `rust-ci.yml` - Comprehensive Rust CI with matrix builds across multiple platforms
5. `cla.yml` - CLA assistant (PR-only)
6. `codex.yml` - Codex AI assistant (label-triggered)
7. `rust-release.yml` - Release builds (tag-triggered)

This created massive redundancy with overlapping checks running simultaneously, leading to:
- Long CI runtimes due to parallel resource contention
- Wasted GitHub Actions minutes
- Complex status checking with multiple required checks
- Difficult debugging when failures occurred

## Solution
**Consolidated into 1 main CI workflow** (`main-ci.yml`) that runs all essential checks in efficient stages:

### Stage 1: Quick Checks (fail fast)
- Spell checking (codespell)
- ASCII compliance checks
- README table of contents validation
- **Time**: ~2-3 minutes

### Stage 2: Node.js/TypeScript
- pnpm dependency installation
- Release staging validation
- **Time**: ~5-8 minutes

### Stage 3: Rust Format & Lint
- `cargo fmt` formatting check
- `cargo clippy` linting
- **Time**: ~3-5 minutes

### Stage 4: Rust Build & Test
- Workspace build with all features
- Individual crate validation
- Test suite execution
- **Time**: ~10-15 minutes

### Stage 5: Docker Integration
- Docker image build
- Container startup and health checks
- Self-check script execution
- **Time**: ~5-10 minutes

## Active Workflows

### Main CI
- **File**: `.github/workflows/main-ci.yml`
- **Triggers**: Push to main, PRs to main
- **Purpose**: Primary CI pipeline with all essential checks

### Specialized Workflows (Kept)
- **CLA Assistant** (`cla.yml`) - CLA signature management
- **Codex AI** (`codex.yml`) - AI-powered code review (label-triggered)
- **Rust Release** (`rust-release.yml`) - Release builds (tag-triggered)

### Disabled Workflows
- `ci.yaml.disabled` - Old Docker-only CI
- `ci.yml.disabled` - Old Node.js CI
- `codespell.yml.disabled` - Standalone spell check
- `rust-ci.yml.disabled` - Old comprehensive Rust CI

## Benefits

1. **Faster CI**: Sequential stages prevent resource contention
2. **Clear Status**: Single required check instead of multiple
3. **Fail Fast**: Quick checks run first to catch obvious issues
4. **Resource Efficient**: No duplicate work across workflows
5. **Maintainable**: Single workflow to maintain and debug
6. **Timeout Protection**: Each stage has appropriate timeout limits

## CI Runtime Comparison

**Before**: 7 workflows running in parallel
- Total CI time: 15-30 minutes (resource contention)
- Success required: All 7 workflows passing
- Debug complexity: High (multiple failure points)

**After**: 1 consolidated workflow with 5 stages  
- Total CI time: 25-40 minutes (sequential, but efficient)
- Success required: 1 workflow passing
- Debug complexity: Low (clear stage-based failure isolation)

## Stage Dependencies

```
quick-checks (fail fast)
├── nodejs-checks
└── rust-format-lint
    └── rust-build-test
        └── docker-integration (needs nodejs-checks + rust-build-test)
            └── ci-success (summary)
```

This dependency structure ensures efficient resource usage and logical flow while maintaining comprehensive testing coverage.
