import importlib.util
from pathlib import Path
import socket
import ssl
import unittest
from unittest.mock import MagicMock,patch

spec=importlib.util.spec_from_file_location('latency_monitor_test',Path(__file__).with_name('status_monitor.py'))
monitor=importlib.util.module_from_spec(spec);spec.loader.exec_module(monitor)


class LatencyTests(unittest.TestCase):
    def test_connect_ack_alone_is_not_timed_as_network_success(self):
        proxy=MagicMock();proxy.recv.return_value=b'HTTP/1.1 200 Connection established\r\n\r\n'
        socket_context=MagicMock();socket_context.__enter__.return_value=proxy
        context=MagicMock();tls=context.wrap_socket.return_value.__enter__.return_value
        with patch.object(monitor.socket,'create_connection',return_value=socket_context),patch.object(monitor,'tls_context',return_value=context),patch.object(monitor.time,'monotonic',side_effect=[100,100.001,100.002,100.14]):
            result=monitor.steam_latency()
        self.assertEqual(result,(140.0,'ready'))
        tls.do_handshake.assert_called_once()
        self.assertEqual(context.wrap_socket.call_args.kwargs['server_hostname'],'store.steampowered.com')
        self.assertFalse(context.wrap_socket.call_args.kwargs['do_handshake_on_connect'])
        sent=proxy.sendall.call_args.args[0]
        self.assertIn(b'CONNECT store.steampowered.com:443',sent)
        self.assertNotIn(b'Authorization',sent)

    def test_timeout_is_not_reported_as_zero_ms(self):
        with patch.object(monitor.socket,'create_connection',side_effect=socket.timeout()):
            self.assertEqual(monitor.steam_latency(),(None,'timeout'))

    def test_proxy_rejection_does_not_start_tls_or_request_auth(self):
        proxy=MagicMock();proxy.recv.return_value=b'HTTP/1.1 407 Proxy Authentication Required\r\n\r\n'
        stream=MagicMock();stream.__enter__.return_value=proxy
        context=MagicMock()
        with patch.object(monitor.socket,'create_connection',return_value=stream),patch.object(monitor,'tls_context',return_value=context):
            self.assertEqual(monitor.steam_latency(),(None,'error'))
        context.wrap_socket.assert_not_called()

    def test_certificate_error_does_not_count_as_ready(self):
        proxy=MagicMock();proxy.recv.return_value=b'HTTP/1.1 200 Connection established\r\n\r\n'
        stream=MagicMock();stream.__enter__.return_value=proxy
        context=MagicMock();context.wrap_socket.return_value.__enter__.return_value.do_handshake.side_effect=ssl.SSLError('synthetic certificate failure')
        with patch.object(monitor.socket,'create_connection',return_value=stream),patch.object(monitor,'tls_context',return_value=context):
            self.assertEqual(monitor.steam_latency(),(None,'error'))

    def test_native_tls_context_verifies_hostname_and_certificate(self):
        context=monitor.tls_context()
        self.assertTrue(context.check_hostname)
        self.assertEqual(context.verify_mode,ssl.CERT_REQUIRED)


if __name__=='__main__':unittest.main()
