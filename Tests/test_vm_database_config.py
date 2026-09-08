"""Storage provisioning must preserve profile settings and run before Hermes starts."""
import copy
import sys
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from talaria_gateway_entry import configure_vm_database, main


class VMDatabaseConfigTests(unittest.TestCase):
    def test_shared_volume_policy_preserves_other_settings_and_is_idempotent(self):
        stored = {'database': {'journal_mode': 'wal', 'cache_size': -16000},
                  'model': {'default': 'existing-model'}, 'custom': '${MY_ENV}'}
        config = Mock()
        config.load_config.side_effect = lambda: copy.deepcopy(stored)
        def save(value, *, merge_existing, preserve_keys):
            self.assertTrue(merge_existing)
            self.assertEqual(set(value), {'database'})
            self.assertIn(('database', 'mmap_size'), preserve_keys)
            stored['database'].update(value['database'])
        config.save_config.side_effect = save
        configure_vm_database(config)
        self.assertEqual(stored['database'], {'journal_mode': 'delete', 'mmap_size': 0,
                                              'synchronous': 'full', 'cache_size': -16000})
        self.assertEqual(stored['custom'], '${MY_ENV}')
        self.assertEqual(stored['model'], {'default': 'existing-model'})
        configure_vm_database(config)
        self.assertEqual(config.save_config.call_count, 1)

    def test_unapplied_or_malformed_configuration_fails_closed(self):
        for database in ({'journal_mode': 'wal'}, 'invalid'):
            config = Mock()
            config.load_config.return_value = {'database': database}
            with self.assertRaises(RuntimeError):
                configure_vm_database(config)

    def test_storage_failure_prevents_gateway_start(self):
        import types
        entry = Mock()
        with patch('talaria_gateway_entry.configure_vm_database', side_effect=OSError('read-only')):
            with patch.dict(sys.modules, {'tui_gateway': types.SimpleNamespace(entry=entry)}):
                with self.assertRaises(OSError):
                    main()
        entry.main.assert_not_called()


if __name__ == '__main__':
    unittest.main()
