"""Transport termination tests independent of Hermes session policy."""
import io
from pathlib import Path
import queue
import sys
import threading
import unittest
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'AgentRuntime'))
from hermes_rpc_transport import HermesRPCTransport


class TransportTests(unittest.TestCase):
    def test_disconnect_releases_rpc_waiters_and_stream_listeners(self):
        transport = HermesRPCTransport.__new__(HermesRPCTransport)
        transport.lock = threading.RLock()
        transport.pending = {'pending': queue.Queue()}
        transport.listeners = {'session': queue.Queue()}
        transport.process = Mock(stdout=io.StringIO('startup diagnostic\n{"method":"event","params":null}\n'))
        transport.disconnected = False
        transport._read()
        self.assertIn('error', transport.pending['pending'].get_nowait())
        self.assertEqual(transport.listeners['session'].get_nowait()['type'], 'error')
        self.assertTrue(transport.disconnected)
        with self.assertRaisesRegex(RuntimeError, 'not running'):
            transport.call('session.status')
        transport.process.stdin.write.assert_not_called()
