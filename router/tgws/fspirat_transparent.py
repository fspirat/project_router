# FSPIRAT: прозрачный режим для tg-ws-proxy (Flowseal) — без настройки прокси в Telegram.
#
# Роутер перенаправляет (nftables, таблица inet fspirat_tg) TCP-соединения устройств дома к адресам Telegram
# на этот порт. Приложение Telegram думает, что говорит с сервером Telegram напрямую, и шлёт обычный
# обфусцированный MTProto-заголовок: ключ — байты 8..40 самого заголовка, без секрета прокси
# (в режиме прокси ключ = SHA-256(байты + секрет)). Дальше соединение идёт тем же путём, что и в
# tg-ws-proxy: WebSocket через Cloudflare к нужному DC. Код tg-ws-proxy не меняется — модуль
# добавляет второй порт поверх его _run() и использует его же функции (do_fallback, bridge, пулы).
#
# Запуск: python3 -m fspirat_transparent --transparent-port 1444 <обычные аргументы tg_ws_proxy>
from __future__ import annotations

import asyncio
import ipaddress
import logging
import socket
import struct
import sys

from proxy import tg_ws_proxy as T
from proxy.utils import (HANDSHAKE_LEN, SKIP_LEN, PREKEY_LEN, KEY_LEN, IV_LEN, PROTO_TAG_POS, DC_IDX_POS,
                         PROTO_TAG_ABRIDGED, PROTO_TAG_INTERMEDIATE, PROTO_TAG_SECURE, ZERO_64)
from proxy.bridge import CryptoCtx, MsgSplitter, do_fallback, bridge_ws_reencrypt
from proxy.raw_websocket import set_sock_opts
from proxy.stats import stats
from proxy.config import proxy_config
from proxy._aes import Cipher, algorithms, modes

log = logging.getLogger('tg-transparent')
SO_ORIGINAL_DST = 80

# Если клиент не указал DC в заголовке — по адресу, к которому он подключался (подсети серверов Telegram).
_DC_BY_NET = [
    ('149.154.175.0/26', 1), ('149.154.175.64/26', 3), ('149.154.175.128/25', 3),
    ('149.154.167.88/29', 4), ('149.154.167.0/24', 2), ('149.154.164.0/22', 4),
    ('149.154.171.0/24', 5), ('91.108.56.0/22', 5), ('91.108.4.0/22', 4), ('91.108.8.0/22', 2),
    ('91.108.12.0/22', 3), ('91.108.16.0/22', 2), ('91.108.20.0/22', 1), ('91.105.192.0/23', 203),
]
_DC_BY_NET = [(ipaddress.ip_network(n), dc) for n, dc in _DC_BY_NET]


def _dc_from_ip(ip: str) -> int:
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return 2
    for net, dc in _DC_BY_NET:
        if a in net:
            return dc
    return 2


def _original_dst(writer) -> str:
    sock = writer.get_extra_info('socket')
    try:
        raw = sock.getsockopt(socket.SOL_IP, SO_ORIGINAL_DST, 16)
        return socket.inet_ntoa(raw[4:8])
    except (OSError, AttributeError):
        return ''


def parse_direct_handshake(handshake: bytes):
    """Обфусцированный заголовок прямого подключения: ключ без секрета. -> (dc, is_media, proto_tag, prekey_iv) | None"""
    prekey_iv = handshake[SKIP_LEN:SKIP_LEN + PREKEY_LEN + IV_LEN]
    dec = Cipher(algorithms.AES(prekey_iv[:PREKEY_LEN]), modes.CTR(prekey_iv[PREKEY_LEN:])).encryptor()
    plain = dec.update(handshake)
    tag = plain[PROTO_TAG_POS:PROTO_TAG_POS + 4]
    if tag not in (PROTO_TAG_ABRIDGED, PROTO_TAG_INTERMEDIATE, PROTO_TAG_SECURE):
        return None
    dc_idx = int.from_bytes(plain[DC_IDX_POS:DC_IDX_POS + 2], 'little', signed=True)
    return abs(dc_idx), dc_idx < 0, tag, prekey_iv


def build_direct_ctx(prekey_iv: bytes, relay_init: bytes) -> CryptoCtx:
    """Как tg_ws_proxy._build_crypto_ctx, но ключи клиента — сырые (как у сервера Telegram), без SHA-256 с секретом."""
    clt_dec = Cipher(algorithms.AES(prekey_iv[:PREKEY_LEN]), modes.CTR(prekey_iv[PREKEY_LEN:])).encryptor()
    rev = prekey_iv[::-1]
    clt_enc = Cipher(algorithms.AES(rev[:PREKEY_LEN]), modes.CTR(rev[PREKEY_LEN:])).encryptor()
    clt_dec.update(ZERO_64)
    r_enc_key = relay_init[SKIP_LEN:SKIP_LEN + PREKEY_LEN]
    r_enc_iv = relay_init[SKIP_LEN + PREKEY_LEN:SKIP_LEN + PREKEY_LEN + IV_LEN]
    r_rev = relay_init[SKIP_LEN:SKIP_LEN + PREKEY_LEN + IV_LEN][::-1]
    tg_enc = Cipher(algorithms.AES(r_enc_key), modes.CTR(r_enc_iv)).encryptor()
    tg_dec = Cipher(algorithms.AES(r_rev[:KEY_LEN]), modes.CTR(r_rev[KEY_LEN:])).encryptor()
    tg_enc.update(ZERO_64)
    return CryptoCtx(clt_dec, clt_enc, tg_enc, tg_dec)


async def handle_transparent(reader, writer):
    stats.connections_total += 1
    stats.connections_active += 1
    peer = writer.get_extra_info('peername')
    dst = _original_dst(writer)
    label = f"auto {peer[0]}:{peer[1]}->{dst}" if peer else "auto"
    set_sock_opts(writer.transport, proxy_config.buffer_size)
    try:
        handshake = await asyncio.wait_for(reader.readexactly(HANDSHAKE_LEN), timeout=10)
        res = parse_direct_handshake(handshake)
        if res is None:
            stats.connections_bad += 1
            log.warning("[%s] не обфусцированный MTProto — пропускаю", label)
            return
        dc, is_media, tag, prekey_iv = res
        if dc == 0 or (dc > 5 and dc < 200):
            dc = _dc_from_ip(dst)
        is_test = dc >= 10000
        if is_test:
            dc -= 10000
        proto_int = (T.PROTO_ABRIDGED_INT if tag == PROTO_TAG_ABRIDGED else
                     T.PROTO_INTERMEDIATE_INT if tag == PROTO_TAG_INTERMEDIATE else T.PROTO_PADDED_INTERMEDIATE_INT)
        relay_init = T._generate_relay_init(tag, -dc if is_media else dc)
        ctx = build_direct_ctx(prekey_iv, relay_init)
        media = " media" if is_media else ""
        try:
            splitter = MsgSplitter(proto_int)
        except Exception:
            splitter = None
        ws = await T.ws_pool.get(dc, is_media, is_test_dc=is_test)
        if ws is not None:
            log.info("[%s] DC%d%s -> WS", label, dc, media)
            stats.connections_ws += 1
            await ws.send(relay_init)
            await bridge_ws_reencrypt(reader, writer, ws, label, ctx, dc=dc, is_media=is_media, splitter=splitter)
            return
        log.info("[%s] DC%d%s -> Cloudflare", label, dc, media)
        ok = await do_fallback(reader, writer, relay_init, label, dc, is_test, is_media, media, ctx,
                               splitter=splitter, h2_pool=T.cf_h2_pool, proto_tag=tag)
        if not ok:
            log.warning("[%s] DC%d%s: нет пути (Cloudflare недоступен)", label, dc, media)
    except (asyncio.TimeoutError, asyncio.IncompleteReadError, ConnectionResetError):
        pass
    except Exception as exc:  # noqa: BLE001
        log.error("[%s] %s", label, exc)
    finally:
        stats.connections_active -= 1
        try:
            writer.close()
            await writer.wait_closed()
        except BaseException:
            pass


def main():
    port = 1444
    argv = sys.argv[1:]
    if '--transparent-port' in argv:
        i = argv.index('--transparent-port')
        port = int(argv[i + 1])
        del argv[i:i + 2]
    sys.argv = [sys.argv[0]] + argv
    orig_run = T._run

    async def run_both(*a, **k):
        srv = await asyncio.start_server(handle_transparent, proxy_config.host, port)
        log.info("  Прозрачный режим: %s:%d (перехват nftables)", proxy_config.host, port)
        try:
            await orig_run(*a, **k)
        finally:
            srv.close()

    T._run = run_both
    T.main()


if __name__ == '__main__':
    main()
