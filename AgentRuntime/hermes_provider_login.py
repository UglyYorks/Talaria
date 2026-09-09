"""Interactive credentials for Hermes providers without a device-code adapter.

Invoked only by the gateway's provider RPC, never through a host shell.
"""
import argparse
import sys


def main():
    from hermes_cli import main as hermes
    from hermes_cli.auth_commands import auth_add_command
    from hermes_cli.provider_catalog import provider_catalog
    slug = sys.argv[1]
    provider = next(row for row in provider_catalog() if row.slug == slug)
    # SDK and external-process providers need the same setup Hermes's picker
    # owns (region/profile, service account, CLI installation/login, etc.).
    if provider.auth_type in {"aws_sdk", "vertex", "external_process", "virtual"}:
        hermes._pick_provider = lambda *args, **kwargs: slug
        hermes.select_provider_and_model()
    else:
        auth_add_command(argparse.Namespace(provider=slug, auth_type="", label="", api_key=None))


if __name__ == "__main__":
    main()
