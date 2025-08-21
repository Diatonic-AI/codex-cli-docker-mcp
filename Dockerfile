# Codex CLI container (production-ready, non-root)
# Base: Node LTS (to install @openai/codex via npm)
FROM node:20-bookworm

# Use existing 'node' user provided by base image
ENV USER=node UID=1000 GID=1000 \
    CODEX_HOME=/home/node/.codex \
    WORKSPACE=/workspace

# Prepare workspace and codex home, owned by node
RUN set -eux; \
    mkdir -p "${CODEX_HOME}" "${WORKSPACE}"; \
    chown -R node:node "${WORKSPACE}" "${CODEX_HOME}"

# Install codex globally and helpful tools
RUN npm install -g @openai/codex@latest \ 
 && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git ca-certificates openssh-client less nano jq curl \ 
 && rm -rf /var/lib/apt/lists/*

# Set up minimal environment
ENV TERM=xterm-256color \
    PAGER=less \
    PATH=/home/${USER}/.local/bin:$PATH

# Copy optional entrypoint helper
COPY ./docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER node
WORKDIR ${WORKSPACE}

# Default command opens a login shell; `codex` can be run directly
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
