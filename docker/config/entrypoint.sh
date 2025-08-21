#!/bin/bash
# Entrypoint script for OpenAI Codex CLI Docker container
# Handles initialization, environment setup, and service startup

set -euo pipefail

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Initialize environment
initialize_environment() {
    log_info "Initializing Codex environment..."
    
    # Ensure directories exist with proper permissions
    mkdir -p "${CODEX_HOME}" "${WORKSPACE_DIR}" "${TOOLS_DIR}" "${AGENTS_DIR}" /logs /config
    
    # Set up Codex home directory structure
    mkdir -p "${CODEX_HOME}"/{auth,logs,config,cache,projects}
    
    # Initialize configuration if not exists
    if [[ ! -f "${CODEX_HOME}/config.toml" ]]; then
        log_info "Creating default Codex configuration..."
        if [[ -f "/config/custom-config.toml" ]]; then
            cp /config/custom-config.toml "${CODEX_HOME}/config.toml"
            log_info "Using custom configuration from /config/custom-config.toml"
        else
            cp /tmp/default-config.toml "${CODEX_HOME}/config.toml" 2>/dev/null || true
        fi
    fi
    
    # Set up workspace permissions
    sudo chown -R codex:codex "${CODEX_HOME}" "${WORKSPACE_DIR}" "${TOOLS_DIR}" "${AGENTS_DIR}"
    chmod -R 755 "${CODEX_HOME}" "${WORKSPACE_DIR}" "${TOOLS_DIR}" "${AGENTS_DIR}"
    
    # Copy authentication if provided
    if [[ -f "/config/auth.json" ]]; then
        log_info "Setting up authentication from mounted config..."
        cp /config/auth.json "${CODEX_HOME}/auth.json"
        chmod 600 "${CODEX_HOME}/auth.json"
    fi
    
    # Set up environment variables
    export RUST_LOG="${RUST_LOG:-info}"
    export RUST_BACKTRACE="${RUST_BACKTRACE:-1}"
    
    log_info "Environment initialization completed"
}

# Check system health
health_check() {
    log_info "Performing health checks..."
    
    # Check Codex binary
    if ! command -v codex &> /dev/null; then
        log_error "Codex binary not found"
        return 1
    fi
    
    # Check Codex version
    if ! codex --version &> /dev/null; then
        log_error "Codex version check failed"
        return 1
    fi
    
    # Check Rust installation
    if ! command -v cargo &> /dev/null; then
        log_error "Rust/Cargo not found"
        return 1
    fi
    
    # Check workspace permissions
    if [[ ! -w "${WORKSPACE_DIR}" ]]; then
        log_error "Workspace directory is not writable"
        return 1
    fi
    
    log_info "All health checks passed"
    return 0
}

# Start development services
start_services() {
    log_info "Starting development services..."
    
    # Start any background services here
    if [[ "${START_SERVICES:-false}" == "true" ]]; then
        log_info "Starting background services..."
        # Add service startup commands here
    fi
    
    # Set up development tools if requested
    if [[ "${SETUP_DEV_TOOLS:-false}" == "true" ]]; then
        setup_development_tools
    fi
}

# Set up development tools
setup_development_tools() {
    log_info "Setting up development tools..."
    
    # Install additional tools if requested
    if [[ -f "/config/install-tools.sh" ]]; then
        log_info "Running custom tool installation script..."
        bash /config/install-tools.sh
    fi
    
    # Install global npm packages for development
    if [[ "${INSTALL_DEV_PACKAGES:-false}" == "true" ]]; then
        log_info "Installing development packages..."
        npm install -g typescript ts-node nodemon @types/node
    fi
    
    # Set up MCP servers if configuration exists
    if [[ -f "/config/mcp-servers.toml" ]]; then
        log_info "Setting up MCP servers configuration..."
        mkdir -p "${CODEX_HOME}/mcp"
        cp /config/mcp-servers.toml "${CODEX_HOME}/config.toml"
    fi
}

# Display system information
show_info() {
    log_info "=== OpenAI Codex CLI Docker Environment ==="
    log_info "Codex Version: $(codex --version)"
    log_info "Rust Version: $(rustc --version)"
    log_info "Node Version: $(node --version)"
    log_info "Python Version: $(python3 --version)"
    log_info "Codex Home: ${CODEX_HOME}"
    log_info "Workspace: ${WORKSPACE_DIR}"
    log_info "Tools Directory: ${TOOLS_DIR}"
    log_info "Agents Directory: ${AGENTS_DIR}"
    log_info "============================================="
}

# Handle signals for graceful shutdown
cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    # Add cleanup logic here
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main execution
main() {
    log_info "Starting OpenAI Codex CLI Docker container..."
    
    # Initialize environment
    initialize_environment
    
    # Perform health checks
    if ! health_check; then
        log_error "Health checks failed, exiting..."
        exit 1
    fi
    
    # Start services
    start_services
    
    # Show system information
    show_info
    
    # Execute the command
    if [[ $# -eq 0 ]] || [[ "$1" == "bash" ]] || [[ "$1" == "sh" ]]; then
        log_info "Starting interactive shell..."
        cd "${WORKSPACE_DIR}"
        exec bash
    elif [[ "$1" == "codex" ]]; then
        log_info "Starting Codex CLI..."
        shift
        cd "${WORKSPACE_DIR}"
        exec codex "$@"
    else
        log_info "Executing command: $*"
        exec "$@"
    fi
}

# Run main function
main "$@"
