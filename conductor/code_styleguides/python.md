# Python Style Guide - minimax-inference

## Overview

This project uses **ruff** for linting and formatting, configured for Python 3.11+.

## Tooling

### Ruff Configuration

Add to `pyproject.toml`:

```toml
[tool.ruff]
target-version = "py311"
line-length = 100

[tool.ruff.lint]
select = [
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "F",      # pyflakes
    "I",      # isort
    "B",      # flake8-bugbear
    "C4",     # flake8-comprehensions
    "UP",     # pyupgrade
    "SIM",    # flake8-simplify
]
ignore = [
    "E501",   # line too long (handled by formatter)
]

[tool.ruff.lint.isort]
known-first-party = ["minimax_inference"]

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
```

### Running Ruff

```bash
# Check for issues
uv run ruff check .

# Auto-fix issues
uv run ruff check --fix .

# Format code
uv run ruff format .
```

---

## Code Style

### Imports

Organize imports in this order (ruff handles automatically):
1. Standard library
2. Third-party packages
3. Local modules

```python
import json
import subprocess
from pathlib import Path

import httpx
from pydantic import BaseModel

from minimax_inference.config import Settings
```

### Type Hints

Use type hints for function signatures:

```python
def download_model(url: str, destination: Path) -> bool:
    """Download model file to destination."""
    ...

def get_model_info(model_name: str) -> dict[str, Any] | None:
    """Retrieve model metadata, or None if not found."""
    ...
```

### String Formatting

Prefer f-strings:

```python
# Good
message = f"Loading model {model_name} from {path}"

# Avoid
message = "Loading model {} from {}".format(model_name, path)
message = "Loading model %s from %s" % (model_name, path)
```

### Path Handling

Use `pathlib.Path` instead of string manipulation:

```python
from pathlib import Path

# Good
model_path = Path.home() / ".cache" / "models" / "minimax-m2.gguf"

# Avoid
model_path = os.path.join(os.path.expanduser("~"), ".cache", "models", "minimax-m2.gguf")
```

---

## Patterns

### Configuration with Pydantic

```python
from pydantic import BaseModel, Field

class InferenceConfig(BaseModel):
    model_path: Path
    context_length: int = Field(default=32768, ge=1024, le=200000)
    temperature: float = Field(default=1.0, ge=0.0, le=2.0)
    port: int = Field(default=8080, ge=1024, le=65535)
```

### Subprocess Execution

```python
import subprocess
from typing import NoReturn

def run_command(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run command with proper error handling."""
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=check,
    )
    return result

def run_or_exit(cmd: list[str]) -> NoReturn | subprocess.CompletedProcess:
    """Run command, exit on failure."""
    try:
        return run_command(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {' '.join(cmd)}")
        print(f"stderr: {e.stderr}")
        raise SystemExit(1)
```

### HTTP Requests with httpx

```python
import httpx

def check_endpoint_health(base_url: str, timeout: float = 5.0) -> bool:
    """Check if inference endpoint is healthy."""
    try:
        response = httpx.get(f"{base_url}/health", timeout=timeout)
        return response.status_code == 200
    except httpx.RequestError:
        return False
```

### CLI Scripts with Rich

```python
from rich.console import Console
from rich.table import Table

console = Console()

def print_status(services: list[dict]) -> None:
    """Display service status table."""
    table = Table(title="Service Status")
    table.add_column("Service", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Port")

    for svc in services:
        table.add_row(svc["name"], svc["status"], str(svc["port"]))

    console.print(table)
```

---

## Error Handling

### Specific Exceptions

Catch specific exceptions, not bare `except`:

```python
# Good
try:
    response = httpx.get(url)
    response.raise_for_status()
except httpx.TimeoutException:
    console.print("[red]Request timed out[/red]")
except httpx.HTTPStatusError as e:
    console.print(f"[red]HTTP error: {e.response.status_code}[/red]")

# Avoid
try:
    response = httpx.get(url)
except:
    print("Something went wrong")
```

### Exit Codes

Use consistent exit codes:

```python
import sys

EXIT_SUCCESS = 0
EXIT_FAILURE = 1
EXIT_CONFIG_ERROR = 2
EXIT_NETWORK_ERROR = 3

def main() -> int:
    try:
        run_setup()
        return EXIT_SUCCESS
    except ConfigurationError:
        return EXIT_CONFIG_ERROR
    except NetworkError:
        return EXIT_NETWORK_ERROR

if __name__ == "__main__":
    sys.exit(main())
```

---

## Project Structure

```
scripts/
├── __init__.py
├── setup.py           # Main setup script
├── download_model.py  # Model download utility
├── benchmark.py       # Performance benchmarking
└── utils/
    ├── __init__.py
    ├── config.py      # Configuration handling
    └── http.py        # HTTP utilities
```

---

## Documentation

### Docstrings

Use Google-style docstrings for complex functions:

```python
def configure_inference(
    model_path: Path,
    context_length: int,
    gpu_layers: int = -1,
) -> dict[str, Any]:
    """Configure inference server settings.

    Args:
        model_path: Path to the GGUF model file.
        context_length: Maximum context window size.
        gpu_layers: Number of layers to offload to GPU (-1 for all).

    Returns:
        Configuration dictionary for the inference server.

    Raises:
        FileNotFoundError: If model_path doesn't exist.
        ValueError: If context_length is out of valid range.
    """
    ...
```

For simple functions, a one-line docstring is sufficient:

```python
def get_gpu_memory() -> int:
    """Return available GPU memory in bytes."""
    ...
```
