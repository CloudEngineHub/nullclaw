#!/usr/bin/env sh
set -eu

list_profiles() {
    cat <<'PROFILES'
ideas      Compact architecture/context bundle for brainstorming contribution ideas.
core       Runtime, CLI, config, gateway, orchestration, and core contracts.
providers  AI provider implementations and provider-facing helpers.
channels   Messaging channel implementations and channel routing.
tools      Tool execution surface, tool implementations, and related policy.
memory     Memory backends, vector/retrieval code, and migration paths.
security   Security, sandbox, gateway, runtime, and risky tool boundaries.
full       All relevant tracked source/docs/examples/config, like the old export.
PROFILES
}

usage() {
    cat <<'USAGE'
Usage: scripts/export-codebase.sh [options]

Build a single-file, review-friendly nullclaw source bundle.

Options:
  -o, --output PATH       Write bundle to PATH
      --repo PATH         Export from another git checkout
      --profile NAME      Export profile (default: ideas)
      --list-profiles     Show available profiles
      --include-vendor   Include vendor/ sources in the full profile
  -h, --help              Show this help

The export is based on git-tracked files, so local build output, caches,
secrets, and ignored files are not included. When --output is omitted, the
default path is nullclaw-codebase-<profile>.md in the repository root.
USAGE
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

repo_arg=""
output_arg=""
profile="ideas"
include_vendor=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|--output)
            [ "$#" -ge 2 ] || die "missing value for $1"
            output_arg=$2
            shift 2
            ;;
        --repo)
            [ "$#" -ge 2 ] || die "missing value for --repo"
            repo_arg=$2
            shift 2
            ;;
        --profile)
            [ "$#" -ge 2 ] || die "missing value for --profile"
            profile=$2
            shift 2
            ;;
        --list-profiles)
            list_profiles
            exit 0
            ;;
        --include-vendor)
            include_vendor=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

case "$profile" in
    ideas|core|providers|channels|tools|memory|security|full) ;;
    *)
        printf 'unknown profile: %s\n\n' "$profile" >&2
        list_profiles >&2
        exit 1
        ;;
esac

if [ -n "$repo_arg" ]; then
    repo_root=$(cd "$repo_arg" && pwd -P)
else
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git checkout"
fi

git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git checkout: $repo_root"

if [ -n "$output_arg" ]; then
    case "$output_arg" in
        /*) output_path=$output_arg ;;
        *) output_path=$(pwd -P)/$output_arg ;;
    esac
else
    output_path=$repo_root/nullclaw-codebase-$profile.md
fi

output_dir=$(dirname "$output_path")
mkdir -p "$output_dir"

output_rel=""
case "$output_path" in
    "$repo_root"/*) output_rel=${output_path#"$repo_root"/} ;;
esac

tmp_manifest=$(mktemp "${TMPDIR:-/tmp}/nullclaw-codebase-manifest.XXXXXX")
tmp_output=$(mktemp "${TMPDIR:-/tmp}/nullclaw-codebase-output.XXXXXX")

cleanup() {
    rm -f "$tmp_manifest" "$tmp_output"
}
trap cleanup EXIT HUP INT TERM

profile_description() {
    case "$profile" in
        ideas) printf 'Compact architecture/context bundle for brainstorming contribution ideas.' ;;
        core) printf 'Runtime, CLI, config, gateway, orchestration, and core contracts.' ;;
        providers) printf 'AI provider implementations and provider-facing helpers.' ;;
        channels) printf 'Messaging channel implementations and channel routing.' ;;
        tools) printf 'Tool execution surface, tool implementations, and related policy.' ;;
        memory) printf 'Memory backends, vector/retrieval code, and migration paths.' ;;
        security) printf 'Security, sandbox, gateway, runtime, and risky tool boundaries.' ;;
        full) printf 'All relevant tracked source/docs/examples/config.' ;;
    esac
}

is_common_context() {
    path=$1

    case "$path" in
        AGENTS.md|CLAUDE.md|README.md|CONTRIBUTING.md|SECURITY.md|LICENSE)
            return 0
            ;;
        build.zig|build.zig.zon|config.example.json)
            return 0
            ;;
        docs/en/README.md|docs/en/architecture.md|docs/en/commands.md|docs/en/development.md)
            return 0
            ;;
        scripts/export-codebase.sh)
            return 0
            ;;
        src/root.zig|src/export_manifest.zig|src/version.zig|src/util.zig|src/json_util.zig|src/http_util.zig)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_ideas_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        docs/en/configuration.md|docs/en/gateway-api.md|docs/en/security.md|docs/en/usage.md)
            return 0
            ;;
        docs/integration-analysis.md|docs/integration-roadmap.md)
            return 0
            ;;
        src/agent.zig|src/agent/context_tokens.zig)
            return 0
            ;;
        src/providers/root.zig|src/providers/factory.zig|src/providers/router.zig)
            return 0
            ;;
        src/channels/root.zig|src/channels/dispatch.zig|src/channel_catalog.zig)
            return 0
            ;;
        src/tools/root.zig|src/tools/schema.zig)
            return 0
            ;;
        src/memory/root.zig|src/runtime.zig|src/security/root.zig)
            return 0
            ;;
        src/peripherals.zig|src/skillforge.zig|src/tunnel.zig|src/mcp.zig)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_core_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/main.zig|src/config.zig|src/config_parse.zig|src/config_types.zig|src/runtime.zig|src/gateway.zig|src/daemon.zig|src/session.zig|src/state.zig)
            return 0
            ;;
        src/agent.zig|src/agent/*.zig|src/bootstrap/*.zig|src/bus.zig|src/inbound_router.zig|src/outbound.zig|src/control_plane.zig|src/health.zig|src/observability.zig|src/capabilities.zig)
            return 0
            ;;
        docs/en/configuration.md|docs/en/gateway-api.md|docs/en/security.md|docs/en/usage.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_providers_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/providers/*|src/provider_names.zig|src/provider_probe.zig|src/list_models.zig|src/model_refs.zig|src/cost.zig|src/sse_client.zig|src/search_base_url.zig|src/config_types.zig)
            return 0
            ;;
        docs/en/configuration.md|docs/en/commands.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_channels_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/channels/*|src/channel_*.zig|src/inbound_*.zig|src/inbound_router.zig|src/outbound.zig|src/bus.zig|src/websocket.zig|src/gateway.zig|src/daemon.zig|src/session.zig)
            return 0
            ;;
        docs/en/external-channels.md|docs/en/gateway-api.md|docs/en/configuration.md)
            return 0
            ;;
        examples/external-channel-template/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_tools_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/tools/*|src/runtime.zig|src/security/policy.zig|src/path_prefix.zig|src/fs_compat.zig|src/cron.zig|src/peripherals.zig|src/hardware.zig)
            return 0
            ;;
        docs/en/security.md|docs/en/commands.md|docs/en/configuration.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_memory_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/memory/*|src/memory/*/*|src/migration.zig|src/rag.zig|src/agent/memory_loader.zig|src/tools/memory_*.zig)
            return 0
            ;;
        docs/en/configuration.md|docs/en/commands.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_security_context() {
    path=$1

    is_common_context "$path" && return 0

    case "$path" in
        src/security/*|src/security/*/*|src/gateway.zig|src/runtime.zig|src/net_security.zig|src/auth.zig|src/identity.zig)
            return 0
            ;;
        src/tools/path_security.zig|src/tools/shell.zig|src/tools/http_request.zig|src/tools/web_fetch.zig|src/tools/browser*.zig)
            return 0
            ;;
        docs/en/security.md|docs/en/gateway-api.md|SECURITY.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_full_context() {
    path=$1

    case "$path" in
        src/*|docs/*|examples/*|spec/*|scripts/*|.github/*|.githooks/*)
            return 0
            ;;
        vendor/*)
            [ "$include_vendor" -eq 1 ] && return 0
            return 1
            ;;
        AGENTS.md|CLAUDE.md|README.md|CONTRIBUTING.md|SECURITY.md|SIGNAL.md|RELEASING.md|LICENSE)
            return 0
            ;;
        build.zig|build.zig.zon|build.zig.zon2json-lock|config.example.json|Dockerfile)
            return 0
            ;;
        docker-compose.yml|docker-compose.signal.yml|flake.nix|flake.lock|run)
            return 0
            ;;
        .dockerignore|.env.example|.envrc|.gitignore)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

profile_includes() {
    path=$1

    case "$profile" in
        ideas) is_ideas_context "$path" ;;
        core) is_core_context "$path" ;;
        providers) is_providers_context "$path" ;;
        channels) is_channels_context "$path" ;;
        tools) is_tools_context "$path" ;;
        memory) is_memory_context "$path" ;;
        security) is_security_context "$path" ;;
        full) is_full_context "$path" ;;
    esac
}

should_include() {
    path=$1

    [ -n "$output_rel" ] && [ "$path" = "$output_rel" ] && return 1

    case "$path" in
        zig-out/*|zig-cache/*|.zig-cache/*|zig-pkg/*|reference/*)
            return 1
            ;;
        nullclaw-codebase*.md)
            return 1
            ;;
        *.png|*.jpg|*.jpeg|*.gif|*.webp|*.ico|*.pdf|*.db|*.db-journal|*.a|*.o|*.wasm)
            return 1
            ;;
    esac

    if [ "$include_vendor" -eq 0 ]; then
        case "$path" in
            vendor/*) return 1 ;;
        esac
    fi

    profile_includes "$path"
}

git -C "$repo_root" ls-files | while IFS= read -r path; do
    if should_include "$path"; then
        printf '%s\n' "$path"
    fi
done > "$tmp_manifest"

file_count=$(wc -l < "$tmp_manifest" | tr -d ' ')
total_bytes=0
while IFS= read -r path; do
    bytes=$(wc -c < "$repo_root/$path" | tr -d ' ')
    total_bytes=$((total_bytes + bytes))
done < "$tmp_manifest"

commit=$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
description=$(profile_description)

{
    printf '# nullclaw Codebase Bundle\n\n'
    printf 'Generated: %s\n' "$generated_at"
    printf 'Commit: %s\n' "$commit"
    printf 'Profile: %s\n' "$profile"
    printf 'Profile description: %s\n' "$description"
    printf 'Files: %s\n' "$file_count"
    printf 'Source bytes: %s\n\n' "$total_bytes"
    printf 'This bundle includes git-tracked files selected by the profile.\n'
    printf 'It skips generated output, local caches, ignored files, binary assets, and vendored dependencies by default.\n\n'
    printf '## File Index\n\n'
    while IFS= read -r path; do
        bytes=$(wc -c < "$repo_root/$path" | tr -d ' ')
        printf -- '- `%s` (%s bytes)\n' "$path" "$bytes"
    done < "$tmp_manifest"
    printf '\n## File Contents\n\n'
    while IFS= read -r path; do
        printf '<<<BEGIN_FILE: %s>>>\n' "$path"
        cat "$repo_root/$path"
        last_char=$(tail -c 1 "$repo_root/$path" 2>/dev/null || printf '\n')
        [ "$last_char" = "" ] || printf '\n'
        printf '<<<END_FILE: %s>>>\n\n' "$path"
    done < "$tmp_manifest"
} > "$tmp_output"

mv "$tmp_output" "$output_path"
printf 'Wrote %s profile with %s files (%s source bytes) to %s\n' "$profile" "$file_count" "$total_bytes" "$output_path"
