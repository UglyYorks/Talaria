"""Hermes plugin: private sessions can use existing memory but cannot add to it."""

PLUGIN = "talaria-incognito"
VERSION = "1.0"
DESCRIPTION = ("Keeps existing memory read-only in Incognito chats and blocks memory changes "
               "and background jobs. Talaria keeps private chat history in temporary storage.")


def catalogue_entry():
    # Bundled availability, not a registration in the normal Hermes process.
    return {"id": PLUGIN, "name": "Talaria Incognito", "version": VERSION,
            "description": DESCRIPTION, "source": "talaria", "scope": "incognito",
            "read_only": True, "enabled": True, "active": False, "error": "",
            "restart_required": False}


def before_tool(tool_name=None, **kwargs):
    if tool_name in {"memory", "skill_manage", "create_notification", "cronjob"}:
        return {"action": "block", "message": "Incognito has read-only memory and skills; changes and background jobs are unavailable."}
    return None


def register(ctx):
    ctx.register_hook("pre_tool_call", before_tool)
