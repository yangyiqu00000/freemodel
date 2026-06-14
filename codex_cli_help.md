# Codex CLI Configuration Reference

## Getting Help

Run these commands in your terminal to see all available options:

```bash
# Main help
codex --help

# Configuration help
codex config --help
```

## Official Documentation

The complete configuration reference is documented at:

- **Config Reference**: https://developers.openai.com/codex/config-reference
- **Basic Config**: https://developers.openai.com/codex/config-basic
- **Advanced Config**: https://developers.openai.com/codex/config-advanced
- **Config Sample**: https://developers.openai.com/codex/config-sample

## Configuration Layers (Precedence Order)

From highest to lowest priority:

1. **Session/CLI arguments** - Command-line flags and environment variables
2. **Project config** - `.codex/config.toml` in current project directory
3. **User config** - `~/.codex/config.toml` or OS-specific config location
4. **System requirements** - `requirements.toml` (admin-enforced settings)
5. **Built-in defaults** - Hardcoded fallback values

## Config File Locations

| Platform | User Config Path |
|----------|-----------------|
| macOS | `~/.codex/config.toml` |
| Linux | `~/.config/codex/config.toml` or `~/.codex/config.toml` |
| Windows | `%LOCALAPPDATA%\OpenAI\Codex\config\config.toml` or `%HOME%\.codex\config.toml` |

## Authentication Methods

### Method 1: ChatGPT Sign-In (Recommended)
```bash
codex auth login
```
- Uses OAuth with your ChatGPT account
- Supports Plus, Pro, Business, Edu, Enterprise plans
- Credentials stored securely in OS keychain

### Method 2: API Key
```bash
# Set environment variable
export OPENAI_API_KEY="your-api-key"

# Or configure via CLI
codex config set api_key "your-api-key"
```

### Method 3: Custom Base URL
For Azure OpenAI or custom endpoints:
```bash
codex config set api_base "https://your-endpoint.openai.azure.com"
codex config set api_version "2024-02-15-preview"
```

## Common Configuration Parameters

Based on standard CLI patterns and the documentation structure, parameters likely include:

### Model Settings
```toml
# ~/.codex/config.toml or .codex/config.toml
[model]
model = "gpt-4-codex"        # Default model
max_tokens = 4096            # Maximum tokens per response
temperature = 0.0            # Sampling temperature (0-2)
top_p = 1.0                  # Nucleus sampling
```

### API Settings
```toml
[api]
base_url = "https://api.openai.com"    # API endpoint
timeout = 60000                        # Request timeout (ms)
max_retries = 3                        # Retry attempts
retry_backoff = 2000                   # Initial backoff (ms)
```

### Request Control (Rate Limiting)
```toml
[rate_limits]
max_concurrent_requests = 5    # Parallel requests
requests_per_minute = 60       # RPM limit (respects your tier)
tokens_per_minute = 40000      # TPM limit (respects your tier)
```

### Execution Policy
```toml
[exec]
allow_network = false          # Allow network access
allow_shell = true             # Allow shell commands
allow_file_write = true        # Allow file modifications
require_confirmation = true    # Confirm before destructive actions
```

### UI/Behavior
```toml
[ui]
theme = "dark"                 # UI theme
auto_submit = false            # Auto-submit when idle
verbose = false                # Detailed output
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | Your OpenAI API key |
| `OPENAI_ORG_ID` | Organization ID for API billing |
| `OPENAI_PROJECT_ID` | Project ID for API billing |
| `OPENAI_BASE_URL` | Override default API base URL |
| `CODEX_CONFIG_PATH` | Override default config file location |
| `DISABLE_TELEMETRY` | Set to `1` to disable telemetry |
| `CODEX_DEBUG` | Set to `1` for debug logging |

## API Key vs Config vs Auth

| Layer | Purpose | Storage | Example |
|-------|---------|---------|---------|
| **Auth** | Identity & billing | Keychain or env var | ChatGPT login, API key |
| **Config** | Behavior settings | TOML files | max_tokens, theme |
| **Session** | Temporary overrides | CLI args | `--model`, `--no-confirm` |

## CLI Commands

```bash
# Authentication
codex auth login              # Sign in with ChatGPT (OAuth)
codex auth logout             # Clear credentials
codex auth status             # Check current auth state

# Configuration
codex config get <key>        # Read a config value
codex config set <key> <val>  # Set a config value
codex config list             # List all config settings
codex config reset            # Reset to defaults

# Session
codex --model "gpt-4"         # Override model for this session
codex --no-confirm            # Skip confirmations
codex --debug                 # Enable debug output
```

## Managed Config (Enterprise)

Admins can enforce settings via `requirements.toml`:

```toml
# requirements.toml (admin-enforced)
[requirements]
min_version = "0.135.0"
max_model = "gpt-4"
force_confirmation = true

# Hooks can also be managed
allow_managed_hooks_only = true
```

## Note on Source of Truth

> **Important**: This reference is compiled from documentation links and standard CLI patterns. For the most accurate and up-to-date parameter list, always check:
> 1. The official config reference: https://developers.openai.com/codex/config-reference
> 2. Your installed version's help: `codex config --help`
> 3. The source code: https://github.com/openai/codex/tree/main/codex-rs/config/src/

The Codex CLI is actively developed (2571 published versions on npm at time of writing), so configuration options may evolve rapidly.