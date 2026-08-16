#!/bin/bash
function az () {
    local opts=()
    if [ -t 0 ] && [ -t 1 ]; then
        opts+=("-it")
    else
        opts+=("-i")
    fi
    podman run "${opts[@]}" -v azure:/root/.azure --rm mcr.microsoft.com/azure-cli:azurelinux3.0 az "$@"
}
