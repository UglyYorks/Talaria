"""Disposable real-Hermes plugin toggle/restart checks. No inference or deliveries.

Run: <Hermes venv>/bin/python -B Tests/hermes_plugins_integration.py <Hermes source>
"""
import os
from pathlib import Path
import sys
import tempfile


def main():
    source = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='talaria-plugins-integration-') as directory:
        home = Path(directory)
        os.environ.update(HERMES_HOME=str(home), HERMES_DISABLE_MCP='1')
        sys.path[:0] = [str(source), str(Path(__file__).resolve().parents[1] / 'AgentRuntime')]
        from hermes_cli import config
        from hermes_notifications import setup, PLUGIN, Notifications
        from hermes_plugins import Plugins
        from hermes_gateway import HermesGateway
        config.save_config({'plugins': {'enabled': [], 'disabled': [], 'entries': {'fixture': {'settings': {'keep': 1}}}},
                            'platform_toolsets': {'cli': ['terminal'], 'cron': ['terminal']}})
        fixture = home / 'plugins' / 'fixture'
        fixture.mkdir(parents=True)
        (fixture / 'plugin.yaml').write_text('name: fixture\nversion: "1.0"\ndescription: "Integration fixture"\n')
        (fixture / '__init__.py').write_text('from hermes_constants import get_hermes_home\ndef register(ctx):\n    (get_hermes_home() / "fixture-loaded").write_text("yes")\n')
        setup(home, 'Native notification policy fixture.')
        service = Plugins()
        plugins = {item['id']: item for item in service.handle({'action': 'list'})['plugins']}
        assert plugins[PLUGIN]['enabled'] and not plugins['fixture']['enabled']
        service.handle({'action': 'set_enabled', 'id': PLUGIN, 'enabled': False})
        notifications = Notifications(home)
        notifications.prepare('Native notification policy fixture.')
        assert notifications.ready.is_set(), 'Disabled plugin must not stop the scheduler'
        assert PLUGIN in config.read_raw_config()['plugins']['disabled'], 'Sync re-enabled a disabled plugin'
        assert config.read_raw_config()['plugins']['entries']['fixture']['settings']['keep'] == 1
        environment = {**os.environ, 'PYTHONPATH': str(source)}
        gateway = HermesGateway(sys.executable, environment, home)
        try:
            result = gateway.call('talaria.plugins', {'action': 'list'})
            plugins = {item['id']: item for item in result['plugins']}
            assert not plugins[PLUGIN]['enabled'] and not plugins[PLUGIN]['active'], plugins[PLUGIN]
            assert not (home / 'fixture-loaded').exists(), 'Listing imported a disabled plugin'
            result = gateway.call('talaria.plugins', {'action': 'set_enabled', 'id': 'fixture', 'enabled': True})
            assert result['restart_required'], result
            assert not (home / 'fixture-loaded').exists(), 'Toggle interrupted runtime registrations'
            gateway.call('talaria.notifications.sync', {'notification_tool_description': 'Native notification policy fixture.'})
            assert PLUGIN in config.read_raw_config()['plugins']['disabled']
        finally:
            gateway.process.terminate(); gateway.process.wait(timeout=10)
        gateway = HermesGateway(sys.executable, environment, home)
        try:
            plugins = {item['id']: item for item in gateway.call('talaria.plugins', {'action': 'list'})['plugins']}
            assert plugins['fixture']['enabled'] and plugins['fixture']['active'], plugins['fixture']
            assert (home / 'fixture-loaded').exists()
            assert not plugins[PLUGIN]['enabled']
            gateway.call('talaria.plugins', {'action': 'set_enabled', 'id': PLUGIN, 'enabled': True})
            gateway.call('talaria.notifications.sync', {'notification_tool_description': 'Native notification policy fixture.'})
            assert PLUGIN in config.read_raw_config()['plugins']['enabled']
        finally:
            gateway.process.terminate(); gateway.process.wait(timeout=10)
        gateway = HermesGateway(sys.executable, environment, home)
        try:
            plugins = {item['id']: item for item in gateway.call('talaria.plugins', {'action': 'list'})['plugins']}
            assert plugins[PLUGIN]['enabled'] and plugins[PLUGIN]['active'], plugins[PLUGIN]
        finally:
            gateway.process.terminate(); gateway.process.wait(timeout=10)
        print('Real Hermes plugin listing, toggle persistence, restart activation, and disabled notification sync passed.')


if __name__ == '__main__': main()
