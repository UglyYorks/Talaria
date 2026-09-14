"""Thinking capabilities from installed Hermes owners, exposed over its TUI RPC.

Do not maintain a second model/effort catalogue. Unknown is distinct from a
model with no reasoning control, and never becomes a made-up effort ladder.
"""


def model_thinking(provider, model, capabilities):
    from hermes_constants import VALID_REASONING_EFFORTS
    from providers import get_provider_profile

    order = ("none", *VALID_REASONING_EFFORTS)
    declared = capabilities.get("supported_efforts")
    mandatory = capabilities.get("can_disable_reasoning") is False
    if capabilities.get("reasoning") is False:
        return {"levels": ["none"], "default": "none"}

    profile = get_provider_profile(provider)
    if declared is None and profile is not None:
        declared = profile.supported_reasoning_efforts(model)
    if declared is None and provider in {"openrouter", "nous"}:
        try:
            from hermes_cli.models_reasoning_caps import (
                openrouter_model_reasoning_capabilities, nous_model_reasoning_capabilities)
        except ModuleNotFoundError as error:
            if error.name != "hermes_cli.models_reasoning_caps":
                raise
            # Hermes moved these owners out of models.py; older installations
            # expose the same capability contract at their original location.
            from hermes_cli.models import (
                openrouter_model_reasoning_capabilities, nous_model_reasoning_capabilities)
        reader = openrouter_model_reasoning_capabilities if provider == "openrouter" else nous_model_reasoning_capabilities
        detail = reader(model, allow_fetch=True)
        if detail is not None:
            if detail.get("supports_reasoning") is False:
                return {"levels": ["none"], "default": "none"}
            declared = detail.get("supported_efforts")
            if declared is None and detail.get("supports_reasoning") is True:
                # In Hermes's OpenRouter schema an omitted effort restriction
                # accepts its full vocabulary. This is a known capability.
                declared = VALID_REASONING_EFFORTS
            mandatory = detail.get("mandatory") is True
            if declared and not mandatory:
                declared = ["none", *declared]
    if declared is None and provider in {"openai-codex", "codex"}:
        from agent.reasoning_effort import codex_supported_efforts
        declared = codex_supported_efforts(model)
    if declared is None and provider == "github-copilot":
        from hermes_cli.models import github_model_reasoning_efforts
        declared = github_model_reasoning_efforts(model) or None
    if declared is None:
        return {"levels": [], "error": "Hermes has not published thinking levels for this model."}
    if not isinstance(declared, (list, tuple)):
        raise ValueError("Invalid Hermes thinking capabilities.")
    if not declared:
        return {"levels": ["none"], "default": "none"}
    levels = [level for level in order if level in declared and not (mandatory and level == "none")]
    if not levels:
        return {"levels": [], "error": "This Hermes version cannot select the published thinking levels."}
    from hermes_cli.config import load_config
    from hermes_constants import resolve_reasoning_config
    config = resolve_reasoning_config(load_config(), provider + "/" + model) or {}
    default = "none" if config.get("enabled") is False else config.get("effort", "medium")
    from agent.reasoning_effort import clamp_effort
    default = clamp_effort(default, levels)
    if default not in levels:
        default = levels[0]
    return {"levels": levels, "default": default}


def describe_thinking(rows):
    result = {}
    for row in rows:
        provider = row.get("slug")
        if not isinstance(provider, str):
            continue
        capabilities = row.get("capabilities") or {}
        for model in row.get("models", []):
            if not isinstance(model, str):
                continue
            try:
                result[provider + "::" + model] = model_thinking(provider, model, capabilities.get(model) or {})
            except (ImportError, AttributeError):
                result[provider + "::" + model] = {"levels": [], "error": "Update Hermes to discover this model's thinking levels."}
            except Exception:
                result[provider + "::" + model] = {"levels": [], "error": "Could not load thinking levels. Try Refresh."}
    return {"models": result}


def register(server):
    server._LONG_HANDLERS = server._LONG_HANDLERS | {"talaria.models.thinking"}
    @server.method("talaria.models.thinking")
    def thinking(rid, params):
        rows = params.get("providers")
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            return server._err(rid, -32602, "A Hermes model catalogue is required.")
        return server._ok(rid, describe_thinking(rows))
