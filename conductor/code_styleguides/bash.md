# Shell/Bash Style Guide - minimax-inference

## Overview

This project follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with adjustments for this infrastructure-focused project. Use **shellcheck** for static analysis.

## Tooling

### Shellcheck

Install and run shellcheck on all scripts:

```bash
# Install (Ubuntu/Debian)
sudo apt install shellcheck

# Run on a script
shellcheck scripts/setup.sh

# Run on all scripts
find scripts/ -name "*.sh" -exec shellcheck {} \;
```

### Shellcheck Directives

Disable specific warnings when necessary (with justification):

```bash
# shellcheck disable=SC2086  # Word splitting is intentional here
docker run $DOCKER_FLAGS "$IMAGE"
```

---

## Script Structure

### Template

```bash
#!/usr/bin/env bash
#
# Brief description of what this script does.
#
# Usage:
#   ./script.sh [options]
#
# Options:
#   -h, --help    Show this help message
#   -v, --verbose Enable verbose output

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
VERBOSE=false

# Functions
usage() {
    grep '^#' "$0" | grep -v '#!/' | cut -c 3-
    exit 0
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        log "$@"
    fi
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

# Main logic
main() {
    log "Starting..."
    # Implementation here
    log "Done."
}

main "$@"
```

---

## Shell Options

### Always Set These

```bash
set -euo pipefail
```

| Option        | Effect                              |
| ------------- | ----------------------------------- |
| `-e`          | Exit on error                       |
| `-u`          | Error on undefined variables        |
| `-o pipefail` | Pipeline fails if any command fails |

### Optional

```bash
set -x  # Debug mode (print commands)
```

---

## Variables

### Naming

- **Constants**: UPPER_SNAKE_CASE, declare with `readonly`
- **Variables**: lower_snake_case
- **Environment exports**: UPPER_SNAKE_CASE

```bash
readonly CONFIG_DIR="/etc/minimax"
readonly DEFAULT_PORT=8080

model_path=""
context_length=32768

export CUDA_VISIBLE_DEVICES=0
```

### Always Quote Variables

```bash
# Good
echo "Model path: $model_path"
cp "$source" "$dest"

# Bad - will break on spaces
echo Model path: $model_path
cp $source $dest
```

### Use Braces for Clarity

```bash
# Good
echo "Using ${model_name}_config.json"

# Ambiguous
echo "Using $model_name_config.json"
```

### Default Values

```bash
# Use default if unset or empty
port="${PORT:-8080}"

# Use default only if unset
port="${PORT-8080}"

# Error if unset
: "${REQUIRED_VAR:?REQUIRED_VAR must be set}"
```

---

## Functions

### Declaration Style

```bash
# Preferred style
function_name() {
    local arg1="$1"
    local arg2="${2:-default}"

    # Implementation
}

# Avoid 'function' keyword
function bad_style {  # Don't do this
    ...
}
```

### Local Variables

Always declare function-local variables:

```bash
process_model() {
    local model_path="$1"
    local output_dir="$2"
    local temp_file

    temp_file=$(mktemp)
    # Use temp_file...
    rm -f "$temp_file"
}
```

### Return Values

Use return codes for success/failure, stdout for data:

```bash
get_gpu_count() {
    nvidia-smi --list-gpus | wc -l
}

check_docker() {
    if command -v docker &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Usage
gpu_count=$(get_gpu_count)
if check_docker; then
    echo "Docker available"
fi
```

---

## Conditionals

### Test Syntax

Use `[[ ]]` for tests (bash-specific, safer):

```bash
# Good
if [[ -f "$file" ]]; then
    echo "File exists"
fi

if [[ "$string" == "value" ]]; then
    echo "Match"
fi

# Avoid [ ] for complex tests
if [ -f "$file" ]; then  # Works but less safe
    echo "File exists"
fi
```

### Common Tests

```bash
# File tests
[[ -f "$path" ]]    # Regular file exists
[[ -d "$path" ]]    # Directory exists
[[ -x "$path" ]]    # Executable
[[ -r "$path" ]]    # Readable
[[ -s "$path" ]]    # Non-empty file

# String tests
[[ -z "$var" ]]     # Empty string
[[ -n "$var" ]]     # Non-empty string
[[ "$a" == "$b" ]]  # String equality
[[ "$a" =~ ^[0-9]+$ ]]  # Regex match

# Numeric tests
[[ "$a" -eq "$b" ]] # Equal
[[ "$a" -lt "$b" ]] # Less than
[[ "$a" -gt "$b" ]] # Greater than
```

---

## Loops

### Iterating Over Files

```bash
# Good - handles spaces in filenames
for file in scripts/*.sh; do
    [[ -f "$file" ]] || continue
    shellcheck "$file"
done

# Good - find with null delimiter
while IFS= read -r -d '' file; do
    process "$file"
done < <(find . -name "*.sh" -print0)

# Bad - breaks on spaces
for file in $(find . -name "*.sh"); do  # Don't do this
    process "$file"
done
```

### Reading Lines

```bash
while IFS= read -r line; do
    echo "Processing: $line"
done < "$input_file"
```

---

## Error Handling

### Check Command Success

```bash
if ! docker pull "$image"; then
    die "Failed to pull image: $image"
fi

# Or with || for one-liners
docker pull "$image" || die "Failed to pull image"
```

### Cleanup on Exit

```bash
cleanup() {
    rm -f "$temp_file"
    docker stop "$container_id" 2>/dev/null || true
}
trap cleanup EXIT

temp_file=$(mktemp)
# Script continues...
# cleanup() runs automatically on exit
```

---

## Command Substitution

### Prefer `$()` Over Backticks

```bash
# Good
current_date=$(date +%Y-%m-%d)
model_size=$(stat -c %s "$model_path")

# Avoid
current_date=`date +%Y-%m-%d`
```

### Check for Command Existence

```bash
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        die "Required command not found: $cmd"
    fi
}

require_command docker
require_command nvidia-smi
require_command curl
```

---

## Output and Logging

### Stderr for Errors

```bash
# Informational to stdout
echo "Starting server on port $port"

# Errors to stderr
echo "ERROR: Port $port already in use" >&2
```

### Structured Logging

```bash
readonly LOG_FILE="${LOG_FILE:-/var/log/minimax/setup.log}"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@" >&2; }
log_error() { log "ERROR" "$@" >&2; }
```

---

## Docker Commands

### Common Patterns

```bash
# Run with GPU support
docker run --rm --gpus all \
    -v "$MODEL_DIR:/models:ro" \
    -p "${PORT}:8080" \
    "$IMAGE" \
    --model /models/minimax-m2.gguf

# Check if container is running
is_container_running() {
    local name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${name}$"
}

# Wait for container health
wait_for_healthy() {
    local name="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)" == "healthy" ]]; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    return 1
}
```

---

## Project-Specific Patterns

### Environment Setup

```bash
setup_environment() {
    # Verify GPU
    if ! nvidia-smi &>/dev/null; then
        die "NVIDIA GPU not available"
    fi

    # Check Docker GPU support
    if ! docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi &>/dev/null; then
        die "Docker GPU support not configured"
    fi

    # Create directories
    mkdir -p "$MODEL_DIR" "$CONFIG_DIR" "$LOG_DIR"
}
```

### Health Checks

```bash
wait_for_endpoint() {
    local url="$1"
    local timeout="${2:-30}"
    local elapsed=0

    log_info "Waiting for $url..."
    while [[ $elapsed -lt $timeout ]]; do
        if curl -sf "$url" &>/dev/null; then
            log_info "Endpoint ready"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    log_error "Timeout waiting for endpoint"
    return 1
}
```
