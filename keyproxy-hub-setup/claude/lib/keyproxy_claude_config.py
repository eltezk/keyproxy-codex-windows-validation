#!/usr/bin/env python3
"""Merge, revert and reset Claude Code settings for KeyProxy."""

import argparse
import copy
import json
import os
import tempfile
from pathlib import Path

BASE_URL = "https://api.keyproxyhub.store/v1"
MODELS_URL = "https://painel.keyproxyhub.store/v1/models"
MCP_SERVER = {
    "type": "http",
    "url": "https://api.keyproxyhub.store/mcp",
    "headers": {"Authorization": "Bearer ${KEYPROXY_API_KEY}"},
}
MODELS = [
    "auto",
    "gpt-5.6-sol",
    "gpt-5.6-terra",
    "gpt-5.6-luna",
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.3-codex",
    "gpt-5.3-codex-xhigh",
    "gpt-5.3-codex-high",
    "gpt-5.3-codex-low",
    "gpt-5.3-codex-none",
]
ENV_VALUES = {
    "ANTHROPIC_BASE_URL": BASE_URL,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION": "KeyProxy — máxima capacidade",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME": "gpt-5.6-sol",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION": "KeyProxy — máxima capacidade",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gpt-5.6-terra",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "gpt-5.6-terra",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION": "KeyProxy — equilíbrio entre capacidade e custo",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gpt-5.6-luna",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "gpt-5.6-luna",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION": "KeyProxy — execução rápida e eficiente com ferramentas",
    "ANTHROPIC_CUSTOM_MODEL_OPTION": "gpt-5.5",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "gpt-5.5",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "KeyProxy — opção premium alternativa",
    "CLAUDE_CODE_SUBAGENT_MODEL": "inherit",
    "KEYPROXY_MODELS_URL": MODELS_URL,
}
MANAGED_ENV_KEYS = set(ENV_VALUES) | {
    "ANTHROPIC_AUTH_TOKEN",
    "KEYPROXY_API_KEY",
    "ANTHROPIC_SMALL_FAST_MODEL",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY",
}
MANAGED_TOP_KEYS = {
    "model",
    "availableModels",
    "enforceAvailableModels",
    "teammateDefaultModel",
    "advisorModel",
}
LEGACY_MANAGED_ENV_KEYS = MANAGED_ENV_KEYS - {
    "KEYPROXY_API_KEY",
    "KEYPROXY_MODELS_URL",
}


def load_object(path: Path):
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path} precisa conter um objeto JSON")
    return data


def atomic_write(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_name, 0o600)
        json.loads(Path(temp_name).read_text(encoding="utf-8"))
        os.replace(temp_name, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise


def settings_env(data):
    if "env" not in data:
        return {}
    env = data["env"]
    if not isinstance(env, dict):
        raise ValueError("settings.env precisa conter um objeto JSON")
    return env


def mcp_servers(data):
    if "mcpServers" not in data:
        return {}
    servers = data["mcpServers"]
    if not isinstance(servers, dict):
        raise ValueError("~/.claude.json.mcpServers precisa conter um objeto JSON")
    return servers


def snapshot(data, claude_data, path_added=None):
    env = settings_env(data)
    servers = mcp_servers(claude_data)
    state = {
        "version": 2,
        "top": {key: {"present": key in data, "value": copy.deepcopy(data.get(key))} for key in MANAGED_TOP_KEYS},
        "env": {key: {"present": key in env, "value": copy.deepcopy(env.get(key))} for key in MANAGED_ENV_KEYS},
        "mcp": {
            "present": "keyproxy" in servers,
            "value": copy.deepcopy(servers.get("keyproxy")),
        },
    }
    if isinstance(path_added, bool):
        state["pathAdded"] = path_added
    return state


def normalize_state(state):
    if not isinstance(state, dict):
        raise ValueError("estado KeyProxy inválido ou incompatível")
    version = state.get("version")
    if version == 1:
        legacy = copy.deepcopy(state)
        values = legacy.get("env")
        if not isinstance(values, dict) or set(values) != LEGACY_MANAGED_ENV_KEYS:
            raise ValueError("estado KeyProxy legado inválido")
        for key in MANAGED_ENV_KEYS - LEGACY_MANAGED_ENV_KEYS:
            values[key] = {"present": False, "value": None}
        legacy["version"] = 2
        legacy["mcp"] = {"present": False, "value": None}
        state = legacy
    if state.get("version") != 2:
        raise ValueError("estado KeyProxy inválido ou incompatível")
    if "pathAdded" in state and not isinstance(state["pathAdded"], bool):
        raise ValueError("estado KeyProxy contém pathAdded inválido")
    for section, keys in (("top", MANAGED_TOP_KEYS), ("env", MANAGED_ENV_KEYS)):
        values = state.get(section)
        if not isinstance(values, dict) or set(values) != keys:
            raise ValueError(f"estado KeyProxy contém seção {section} inválida")
        for key in keys:
            item = values.get(key)
            if not isinstance(item, dict) or not isinstance(item.get("present"), bool):
                raise ValueError(f"estado KeyProxy contém item {section}.{key} inválido")
    mcp = state.get("mcp")
    if not isinstance(mcp, dict) or not isinstance(mcp.get("present"), bool):
        raise ValueError("estado KeyProxy contém snapshot MCP inválido")
    return state


def valid_state(state):
    try:
        normalize_state(state)
        return True
    except ValueError:
        return False


def is_managed(data):
    env = data.get("env") if isinstance(data.get("env"), dict) else {}
    return (
        env.get("ANTHROPIC_BASE_URL") == BASE_URL
        and isinstance(env.get("ANTHROPIC_AUTH_TOKEN"), str)
        and bool(env.get("ANTHROPIC_AUTH_TOKEN"))
        and data.get("model") == "gpt-5.6-sol"
        and data.get("availableModels") == MODELS
        and data.get("enforceAvailableModels") is True
    )


def apply_snapshot(data, claude_data, state):
    state = normalize_state(state)
    result = copy.deepcopy(data)
    env = settings_env(result)
    result["env"] = env
    for key, item in state.get("top", {}).items():
        if item.get("present"):
            result[key] = copy.deepcopy(item.get("value"))
        else:
            result.pop(key, None)
    for key, item in state.get("env", {}).items():
        if item.get("present"):
            env[key] = copy.deepcopy(item.get("value"))
        else:
            env.pop(key, None)
    if not env:
        result.pop("env", None)

    claude_result = copy.deepcopy(claude_data)
    servers = mcp_servers(claude_result)
    claude_result["mcpServers"] = servers
    if state["mcp"]["present"]:
        servers["keyproxy"] = copy.deepcopy(state["mcp"].get("value"))
    else:
        servers.pop("keyproxy", None)
    if not servers:
        claude_result.pop("mcpServers", None)
    return result, claude_result


def configured(data, token):
    result = copy.deepcopy(data)
    env = settings_env(result)
    result["env"] = env
    env.update(ENV_VALUES)
    env["ANTHROPIC_AUTH_TOKEN"] = token
    env["KEYPROXY_API_KEY"] = token
    env.pop("ANTHROPIC_SMALL_FAST_MODEL", None)
    env.pop("CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY", None)
    result["model"] = "gpt-5.6-sol"
    result["availableModels"] = MODELS
    result["enforceAvailableModels"] = True
    result.pop("teammateDefaultModel", None)
    result.pop("advisorModel", None)
    return result


def configured_mcp(data):
    result = copy.deepcopy(data)
    servers = mcp_servers(result)
    existing = servers.get("keyproxy")
    if existing is not None and existing != MCP_SERVER:
        raise ValueError("já existe um servidor MCP 'keyproxy' divergente")
    result["mcpServers"] = servers
    servers["keyproxy"] = copy.deepcopy(MCP_SERVER)
    return result


def reset_default(data, claude_data):
    result = copy.deepcopy(data)
    env = settings_env(result)
    for key in MANAGED_ENV_KEYS:
        env.pop(key, None)
    if env:
        result["env"] = env
    else:
        result.pop("env", None)
    for key in MANAGED_TOP_KEYS:
        result.pop(key, None)

    claude_result = copy.deepcopy(claude_data)
    servers = mcp_servers(claude_result)
    existing = servers.get("keyproxy")
    if existing is not None and existing != MCP_SERVER:
        raise ValueError(
            "o servidor MCP 'keyproxy' está divergente; reset recusado para não remover configuração não gerenciada"
        )
    if existing == MCP_SERVER:
        servers.pop("keyproxy")
    if servers:
        claude_result["mcpServers"] = servers
    else:
        claude_result.pop("mcpServers", None)
    return result, claude_result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("install", "revert", "reset", "validate"))
    parser.add_argument("--settings", required=True, type=Path)
    parser.add_argument("--claude-config", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--token-stdin", action="store_true")
    parser.add_argument("--path-added", choices=("true", "false"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    current = load_object(args.settings)
    claude_current = load_object(args.claude_config)
    output = current
    claude_output = claude_current

    if args.command == "install":
        if not args.token_stdin:
            parser.error("--token-stdin é obrigatório para install")
        token = os.read(0, 1024 * 1024).decode("utf-8").rstrip("\r\n")
        if not token:
            parser.error("o token recebido por stdin está vazio")
        claude_output = configured_mcp(claude_current)
        preserve_state = False
        if is_managed(current):
            if not args.state.exists():
                raise ValueError(
                    "a configuração KeyProxy está ativa, mas o snapshot original está ausente"
                )
            existing_state = load_object(args.state)
            if not valid_state(existing_state):
                raise ValueError("estado KeyProxy existente é inválido")
            preserve_state = True
        state = None if preserve_state else snapshot(
            current,
            claude_current,
            args.path_added == "true" if args.path_added else None,
        )
        output = configured(current, token)
        token = ""
        if not args.dry_run and state is not None:
            args.state.parent.mkdir(parents=True, exist_ok=True)
            atomic_write(args.state, state)
    elif args.command == "revert":
        state = load_object(args.state)
        output, claude_output = apply_snapshot(current, claude_current, state)
    elif args.command == "reset":
        output, claude_output = reset_default(current, claude_current)
    elif args.command == "validate":
        env = current.get("env", {})
        clean_settings, clean_claude = reset_default(current, claude_current)
        expected = configured(clean_settings, env.get("ANTHROPIC_AUTH_TOKEN", ""))
        expected_claude = configured_mcp(clean_claude)
        if (
            not env.get("ANTHROPIC_AUTH_TOKEN")
            or env.get("KEYPROXY_API_KEY") != env.get("ANTHROPIC_AUTH_TOKEN")
            or current != expected
            or claude_current != expected_claude
        ):
            raise SystemExit("Configuração KeyProxy divergente")
        print("configuration=ok")
        return

    if args.dry_run:
        print("dry-run=ok")
        return

    atomic_write(args.settings, output)
    atomic_write(args.claude_config, claude_output)
    print(f"settings={args.settings}")
    print(f"claude_config={args.claude_config}")
    print(f"{args.command}=ok")


if __name__ == "__main__":
    main()
