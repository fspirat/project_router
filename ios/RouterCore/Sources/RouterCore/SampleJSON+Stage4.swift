// Generated from the stage 4 client contract (contract-stage4.md §2, §3.3, §10) and the observed responses of the
// real app.php (scratchpad/stage4h/out4.txt). Reference time: `SampleJSON.now`.
// No real addresses, tokens or secrets: MACs/IPs are documentation ranges, ids and confirms are dummies.

extension SampleJSON {
    /// Contract-stage4 §10.1.
    public static let statusStage4: String = #"""
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":48,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Rt5Vb8Nw","name":"fspiratDE","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"},{"id":"Pz1Yc4Ue","name":" 🇳🇱 Нидерланды ","ms":63,"group":"nosok"},{"id":"Wm6Tj2Gk","name":"🇫🇮 Финляндия","ms":0,"group":"nosok"},{"id":"Bx2Kd7Lr","name":"🇸🇪 Швеция","ms":89,"group":"Reserve"},{"id":"Cy8Np3Vt","name":"🇵🇱 Польша","ms":0,"group":"Reserve"}]},"log":["13.10 13:20 вручную -> Kq7Lm2Xp","13.10 13:40 перезапуск VPN","13.10 13:55 MyDirect + gosuslugi.ru","13.10 14:02 мимо VPN: 00:00:5e:00:53:02"],"history":[[1791885900,52],[1791886200,48]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":112}]},"sub":{"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800,"title":"nosok"},"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14,"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800},{"id":"cfg7d8e9f","name":"Reserve","host":"r.example.org","hwid":false,"nodes":6}],"svc_direct":["Хайпиксель"],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/","mc|Хайпиксель|mc.example.net:25565"],"svc":{"Kq7Lm2Xp":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":112}]},"Hd3Fs9Qa":{"ts":1791884590,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":88},{"kind":"web","name":"Discord","host":"discord.com","vpn":95},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":102},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":140}]},"Pz1Yc4Ue":{"ts":1791884600,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":38},{"kind":"web","name":"Discord","host":"discord.com","vpn":71},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":97}]},"direct":{"ts":1791884410,"base":9,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0},{"kind":"mc","name":"Хайпиксель","host":"mc.example.net","vpn":31}]}},"svc_running":false,"speed":{"vpn":{"via":"vpn","ts":1791880000,"down":91234567,"up":40123456,"latency":38,"ip":"203.0.113.77","country":"NL","server":"Hetzner (Германия)","streams":4,"up_limited":false},"direct":{"via":"direct","ts":1791879000,"down":286000000,"up":0,"latency":6,"ip":"198.51.100.20","country":"RU","server":"Selectel (Россия)","streams":4,"up_limited":true}},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-51,"rate":866,"up":120394882,"dn":2349872311},{"name":"","ip":"192.168.1.40","mac":"00:00:5e:00:53:02","online":true,"band":"wired","up":10392,"dn":88123,"direct":true},{"name":"tv-living","ip":"192.168.1.51","mac":"00:00:5e:00:53:03","online":true,"band":"2g","signal":-68,"rate":72,"up":0,"dn":0,"sched":"2300-0700"},{"name":"ipad","ip":"192.168.1.41","mac":"00:00:5e:00:53:05","online":true,"band":"5g","signal":-77,"rate":144,"up":1000,"dn":5000,"sblocked":true,"sched":"1300-1500"},{"name":"old-laptop","ip":"192.168.1.77","mac":"00:00:5e:00:53:04","online":false,"up":0,"dn":0,"blocked":true},{"name":"","ip":"192.168.1.90","mac":"ae:00:5e:00:53:06","online":false,"up":0,"dn":0}],"sys":{"cpu":7,"cores":2,"load":"0.21 0.17 0.15","mem_total":245632,"mem_avail":121840,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3460,"temp":null,"uptime":352812,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":61344,"net":{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}}}
"""#

    /// Contract-stage4 §10.2.
    public static let dataWeek: String = #"""
{"now":1791886560,"range":"week","step":1800,"points":[[1791873900,52,0,0],[1791875700,49,1,0],[1791877500,0,2,0],[1791879300,-1,0,30],[1791881100,50,0,2],[1791882900,47,0,0],[1791884700,48,0,0],[1791886500,50,0,0]],"stats":{"avg":50,"min":38,"max":71,"fails":3,"offline_min":32},"events":[[1791886200,"manual","Сервер выбран вручную: fspiratNL"],[1791883800,"restart","Перезапуск VPN"],[1791857400,"auto","Автопереключение: fspiratDE -> fspiratNL 41ms"],[1791820000,"online","Роутер снова на связи (не было 6 мин)"],[1791819640,"offline","Роутер пропал со связи"],[1791700000,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02)"],[1791600000,"reboot","Роутер перезагрузился"]],"offline_since":null,"last_ok":1791886530,"names":{"5a:00:5e:00:53:01":"iPhone владельца"},"tpoints":{"YouTube":[[1791882900,61],[1791884700,0],[1791886500,58]],"Discord":[[1791884700,0]]},"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[734003200,28991029248]},"00:00:5e:00:53:02":{"d":[1048576,10485760],"m":[20971520,209715200]}},"speed":[[1791879000,"direct",286000000,0,6],[1791880000,"vpn",91234567,40123456,38]],"mtg":null,"site":{"luci":"https://router.fspirat.xyz/","bot":"FSRouter_bot","mtg":"","panels":["fspirat.xyz"]},"newdevs":[{"ts":1791700000,"mac":"00:00:5e:00:53:02"}]}
"""#

    /// Contract-stage4 §10.3.
    public static let dataMonth: String = #"""
{"now":1791886560,"range":"month","step":7200,"points":[[1791867600,51,0,0],[1791874800,49,3,0],[1791882000,0,5,0],[1791889200,50,0,0]],"stats":{"avg":50,"min":38,"max":71,"fails":8,"offline_min":0},"events":[],"offline_since":null,"last_ok":1791886530,"names":{},"tpoints":{},"traffic":{},"speed":[],"mtg":null,"site":{"luci":"","bot":"","mtg":"","panels":[]},"newdevs":[]}
"""#

    /// Contract-stage4 §2.2 observed (the "…" element is skipped by the lenient decoder).
    public static let dataWeekObserved: String = #"""
{"now":1791899278,"range":"week","step":1800,"points":[[1791294300,51,0,0],"…",[1791899100,49,0,0]],"stats":{"avg":51,"min":40,"max":62,"fails":103,"offline_min":9},"events":[[1791899216,"manual","Сервер выбран вручную: _direct"],[1791896276,"router","MyDirect + gosuslugi.ru"],[1791812876,"auto","Автопереключение: fspiratDE -> fspiratNL 41ms"],[1791726876,"online","Роутер снова на связи (не было 6 мин)"],[1791726476,"offline","Роутер пропал со связи"],[1791380876,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02)"]],"newdevs":[{"ts":1791380876,"mac":"00:00:5e:00:53:02"}],"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[52429800,1610614736]}},"names":{},"tpoints":{"YouTube":[[1791891900,61],[1791899100,0]],"Discord":[[1791899100,0]]},"speed":[[1791894276,"vpn",91234567,40123456,38],[1791893276,"direct",286000000,0,6]],"site":{"luci":"https://router.panel.example.test/","bot":"TestBot","mtg":"","panels":["panel.example.test"]},"offline_since":null,"last_ok":1791899246,"mtg":null}
"""#

    /// Contract-stage4 §2.3 observed (`zapret_on.json`).
    public static let zapretOn: String = #"""
{"installed":true,"enabled":true,"strategy":2,"engine":true,"nft":true,"route_cfg":true,"route_live":true,"fallback":false,"error":"","pkts_tcp":18234,"pkts_udp":5120,"vpn_excluded":1,"version":"v72.5","busy":false,"checking":false,"check":{"ts":1791886000,"via":"isp","list":[{"name":"YouTube","ok":true,"code":"204","ms":412,"queued":6},{"name":"YouTube видео","ok":true,"code":"200","ms":530,"queued":6},{"name":"Discord API","ok":true,"code":"200","ms":610,"queued":5},{"name":"Discord CDN","ok":false,"code":"000","ms":12001,"queued":0}]}}
"""#

    /// `zapret_partial.json`.
    public static let zapretPartial: String = #"""
{"installed":true,"enabled":true,"strategy":3,"engine":false,"nft":true,"route_cfg":true,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":1,"version":"v72.5","busy":false,"checking":false,"check":null}
"""#

    /// `zapret_fallback.json`.
    public static let zapretFallback: String = #"""
{"installed":true,"enabled":true,"strategy":3,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":true,"error":"nfqws не запускается — YouTube и Discord временно идут через VPN","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"v72.5","busy":false,"checking":false,"check":{"error":"xray"}}
"""#

    /// `zapret_busy.json`.
    public static let zapretBusy: String = #"""
{"installed":true,"enabled":false,"strategy":1,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"v72.5","busy":true,"checking":false,"check":null}
"""#

    /// `zapret_off_checking.json`.
    public static let zapretOffChecking: String = #"""
{"installed":true,"enabled":false,"strategy":3,"engine":true,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"","busy":false,"checking":true,"check":null}
"""#

    /// `zapret_not_installed.json`.
    public static let zapretNotInstalled: String = #"""
{"installed":false,"enabled":false,"strategy":3,"engine":false,"nft":false,"route_cfg":false,"route_live":false,"fallback":false,"error":"","pkts_tcp":0,"pkts_udp":0,"vpn_excluded":0,"version":"","busy":false,"checking":false,"check":null}
"""#

    /// `zapret_absent.json`.
    public static let zapretAbsent: String = #"""
{"installed":false,"absent":true}
"""#

    /// Contract-stage4 §2.4 observed (`tgws_on.json`).
    public static let tgwsOn: String = #"""
{"installed":true,"auto":true,"redirected":3412,"enabled":true,"running":true,"listening":true,"host":"192.168.1.1","port":1443,"version":"1.1.3"}
"""#

    /// `tgws_starting.json`.
    public static let tgwsStarting: String = #"""
{"installed":true,"auto":false,"redirected":0,"enabled":true,"running":true,"listening":false,"host":"192.168.1.1","port":1443,"version":"1.1.3"}
"""#

    /// `tgws_off.json`.
    public static let tgwsOff: String = #"""
{"installed":true,"auto":false,"redirected":0,"enabled":false,"running":false,"listening":false,"host":"192.168.1.1","port":1443,"version":"1.1.3"}
"""#

    /// `tgws_absent.json`.
    public static let tgwsAbsent: String = #"""
{"installed":false,"absent":true}
"""#

    /// `mydirect.json`.
    public static let mydirect: String = #"""
{"domains":["kinopoisk.ru","gosuslugi.ru","sberbank.ru","geosite:category-ru","mc.example.net"],"added":["kinopoisk.ru"]}
"""#

    /// `mydirect_norule.json` (500).
    public static let mydirectNoRule: String = #"""
{"error":"no rule","message":"В PassWall нет правила MyDirect.","source":"router"}
"""#

    /// `vds.json`.
    public static let vds: String = #"""
{"ts":1791886440,"servers":[{"name":"Сервер панели","local":true,"stat":{"up":1209600,"cores":2,"mem_total":2014084,"mem_avail":1302500,"rx":918273645123,"tx":905172634512,"conns":14,"load":"0.08 0.05 0.01","disk":"37%","xray":"active"}},{"name":"DE","stat":null},{"name":"NL2","stat":{"up":86400,"cores":1,"mem_total":1000000,"mem_avail":200000,"rx":1048576,"tx":2097152,"conns":0,"load":"0.50 0.40 0.30","disk":"81%","xray":"inactive"}}]}
"""#

    /// Contract-stage4 §2.6 observed.
    public static let vdsObserved: String = #"""
{"ts":1791899156,"servers":[{"name":"Сервер панели","local":true,"stat":{"up":1209600,"cores":2,"mem_total":2014084,"mem_avail":1302500,"rx":918273645123,"tx":905172634512,"conns":14,"load":"0.08 0.05 0.01","disk":"37%","xray":"active"}},{"name":"DE","stat":null},{"name":"NL2","stat":{"up":86400,"cores":1,"mem_total":1000000,"mem_avail":200000,"rx":1,"tx":2,"conns":0,"load":"0.50 0.40 0.30","disk":"81%","xray":"inactive"}}]}
"""#

    /// `vds_empty.json`.
    public static let vdsEmpty: String = #"""
{"ts":null,"servers":[]}
"""#

    /// `devices_access.json`.
    public static let accessList: String = #"""
{"apps":[{"id":"49139e3a1db5a6ac","name":"iPhone владельца","model":"iPhone18,1","os":"iOS 26.0","app":"1.1 (20)","created":1791886000,"seen":1791886500,"last_ip":"203.0.113.50","expires":1799662500,"hard_expires":1823422000,"current":true},{"id":"8df5a0cb8a35a59a","name":"Второй iPhone","model":"iPhone16,1","os":"18.1","app":"1.0 (12)","created":1790000000,"seen":1791713760,"last_ip":"198.51.100.7","expires":1792400000,"hard_expires":1821536000,"current":false}],"web":[{"ref":"8207c706de3f72c7","created":1791880000,"seen":1791886300,"ip":"203.0.113.50","ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36","current":false}],"logins":[{"ts":1791886000,"name":"iPhone владельца","ip":"203.0.113.50","result":"issued"},{"ts":1791885000,"name":"iPhone","ip":"198.51.100.99","result":"denied"}],"auth_log":[{"ts":1791886000,"what":"APP_OK","ip":"203.0.113.50"},{"ts":1791885990,"what":"APP_LOGIN","ip":"203.0.113.50"},{"ts":1791885000,"what":"APP_DENIED","ip":"198.51.100.99"},{"ts":1791880000,"what":"OK","ip":"203.0.113.50"},{"ts":1791879900,"what":"CODE","ip":"203.0.113.50"},{"ts":1791870000,"what":"FAIL","ip":"203.0.113.51"}]}
"""#

    /// Contract-stage4 §2.7 observed.
    public static let accessListObserved: String = #"""
{"apps":[{"id":"46740d2bc16e6a9d","name":"iPhone владельца","model":"iPhone15,2","os":"iOS 18.1","app":"1.0","created":1791899277,"seen":1791899277,"last_ip":"127.0.0.1","expires":1799675277,"hard_expires":1823435277,"current":true},{"id":"8df5a0cb8a35a59a","name":"Второй iPhone","model":"iPhone16,1","os":"iOS 26.0","app":"1.0 (12)","created":1791899277,"seen":1791726477,"last_ip":"198.51.100.7","expires":1799675277,"hard_expires":1823435277,"current":false}],"web":[{"ref":"8207c706de3f72c7","created":1791899277,"seen":1791899277,"ip":"203.0.113.50","ua":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/141.0","current":false}],"logins":[],"auth_log":[{"ts":1791897476,"what":"CODE","ip":"203.0.113.50"},{"ts":1791895676,"what":"FAIL","ip":"203.0.113.51"},{"ts":1791892076,"what":"OK","ip":"203.0.113.50"}]}
"""#

    /// §10.9 pingone.
    public static let pingOneResult: String = #"""
{"id":"Wm6Tj2Gk","ms":7,"ts":1791899279}
"""#

    /// §10.9.
    public static let okResult: String = #"""
{"ok":true}
"""#

    /// §10.9 block.
    public static let blockResult: String = #"""
{"ok":true,"mac":"00:00:5e:00:53:03","blocked":true}
"""#

    /// §10.9 unblock.
    public static let unblockResult: String = #"""
{"ok":true,"mac":"00:00:5e:00:53:03","blocked":false}
"""#

    /// §10.9 direct.
    public static let directResult: String = #"""
{"ok":true,"direct":true}
"""#

    /// §10.9 diradd/dirdel already done.
    public static let sameResult: String = #"""
{"ok":true,"same":true}
"""#

    /// §10.9 rename.
    public static let renameResult: String = #"""
{"ok":true,"names":{"00:00:5e:00:53:03":"Телевизор","00:00:5e:00:53:02":"Приставка"}}
"""#

    /// §10.9 revoke-all.
    public static let revokeAllResult: String = #"""
{"ok":true,"revoked":7}
"""#

    /// §10.9 speedtest 202.
    public static let speedtestJobStart: String = #"""
{"job":"34045d1894d672ac","poll_every":3}
"""#

    /// §10.9 speedtest job done.
    public static let speedtestJobDone: String = #"""
{"state":"done","action":"speedtest","http":200,"result":{"via":"vpn","ts":1791899279,"down":90000000,"up":40000000,"latency":12,"ip":"203.0.113.77","country":"DE","server":"Hetzner (Германия)","streams":4,"up_limited":false}}
"""#

    /// §10.9 speedtest job: router busy.
    public static let speedtestJobBusy: String = #"""
{"state":"error","action":"speedtest","http":409,"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}
"""#

    /// §10.10.
    public static let errBadNode: String = #"""
{"error":"bad node","message":"Такого сервера нет — обнови список.","source":"router"}
"""#

    /// §10.10.
    public static let errTime: String = #"""
{"error":"time","message":"Неверное время.","source":"router"}
"""#

    /// §10.10.
    public static let errNoTarget: String = #"""
{"error":"no target","message":"Нет такого сервиса.","source":"router"}
"""#

    /// §10.10.
    public static let errNft: String = #"""
{"error":"nft","message":"Роутер не смог изменить правила.","source":"router"}
"""#

    /// §10.10.
    public static let errNoRule: String = #"""
{"error":"no rule","message":"В PassWall нет правила MyDirect.","source":"router"}
"""#

    /// §10.10.
    public static let errNotInstalled: String = #"""
{"error":"not installed","message":"Не установлено на роутере.","source":"router"}
"""#

    /// §10.10.
    public static let errRouterBusy: String = #"""
{"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}
"""#

    /// §10.10.
    public static let errDirdelNotAdded: String = #"""
{"error":"bad_param","message":"Убрать можно только домены, добавленные из панели или приложения."}
"""#

    /// §10.10.
    public static let errTooLong: String = #"""
{"error":"too_long","message":"Слишком длинное значение."}
"""#

    /// §10.10.
    public static let errRateLimited: String = #"""
{"error":"rate_limited","message":"Слишком часто — подожди немного.","retry_after":30}
"""#

    /// §10.10.
    public static let errNotFound: String = #"""
{"error":"not_found","message":"Не найдено."}
"""#

    /// §10.10.
    public static let errConfirmInvalid: String = #"""
{"error":"confirm_invalid","message":"Подтверждение не подошло — повтори действие."}
"""#

    /// 428 observed (scratchpad/stage4h/out4.txt).
    public static let confirmSwitchNode: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"ea66e344f7d0a0a8f140aef4d38eeb04","expires_in":60,"danger":"high","title":"Подключить «🇩🇪 Германия»?","text":"VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Подключить"}
"""#

    /// 428 observed.
    public static let confirmSwitchCurrent: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"329fc943bead1646d2b55e27f271700f","expires_in":60,"danger":"high","title":"Подключить «fspiratNL»?","text":"Этот сервер уже подключён. VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Подключить"}
"""#

    /// 428 observed.
    public static let confirmSwitchDead: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"036fd2bca4661cc3c46d27ad7ebe010b","expires_in":60,"danger":"high","title":"Подключить «🇫🇮 Финляндия»?","text":"VPN перезапустится, связь через VPN пропадёт на несколько секунд. Сервер сейчас не отвечает — дом может остаться без VPN до автопереключения (~10 мин).","button":"Подключить"}
"""#

    /// 428 observed.
    public static let confirmSwitchUnknown: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"2f10023222dbafe7d46a1a5ac664096e","expires_in":60,"danger":"high","title":"Подключить другой сервер?","text":"VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Подключить"}
"""#

    /// 428 observed (critical).
    public static let confirmSwitchDirect: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"b9010e18784bb2bcbdc6aafd828d7721","expires_in":60,"danger":"critical","title":"Пустить весь трафик напрямую, без VPN?","text":"Весь трафик пойдёт без VPN, с IP провайдера; автопереключение отключится. Правила Split остаются: MyDirect — напрямую, YouTube и Discord — через zapret, если он включён. Вернуть VPN — выбрать сервер. Связь пропадёт на несколько секунд.","button":"Напрямую"}
"""#

    /// 428 observed.
    public static let confirmSubupdateSid: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"10bbd69cf4bf974c64d6d6eb34b0ae78","expires_in":60,"danger":"high","title":"Обновить подписку «Reserve»?","text":"Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой.","button":"Обновить"}
"""#

    /// 428 observed.
    public static let confirmSubupdateAll: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"695c998d6068f6f5897611ef9a4d92a6","expires_in":60,"danger":"high","title":"Обновить подписки VPN?","text":"Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой.","button":"Обновить"}
"""#

    /// 428 observed.
    public static let confirmBlockNamed: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"d1950c072a269509481061f35d69ebf5","expires_in":60,"danger":"high","title":"Выключить интернет устройству?","text":"«Телевизор» (00:00:5e:00:53:03) останется в Wi-Fi, но сайты и приложения перестанут открываться, пока не включишь обратно. Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.","button":"Выключить интернет"}
"""#

    /// 428 observed.
    public static let confirmBlockUnnamed: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"14c808665dc12f38099e478f067c9f4e","expires_in":60,"danger":"high","title":"Выключить интернет устройству?","text":"Устройство 00:00:5e:00:53:04 останется в Wi-Fi, но сайты и приложения перестанут открываться, пока не включишь обратно. Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.","button":"Выключить интернет"}
"""#

    /// 428 observed.
    public static let confirmDirectOn: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"f92bc9855d56083fd1f986529759dcd6","expires_in":60,"danger":"high","title":"Пускать устройство мимо VPN?","text":"«Телевизор» (00:00:5e:00:53:03) будет ходить в интернет напрямую, как без VPN; заблокированные в России сайты на нём открываться не будут. VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Мимо VPN"}
"""#

    /// 428 observed.
    public static let confirmDirectOff: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"31686c01ddd039330cdc1cf38ff88902","expires_in":60,"danger":"high","title":"Пускать устройство снова через VPN?","text":"Устройство 00:00:5e:00:53:02 снова пойдёт через VPN. VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Через VPN"}
"""#

    /// 428 observed (medium).
    public static let confirmSchedule: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"4d04926fe9ee90be9407a94746cb0920","expires_in":60,"danger":"medium","title":"Включить расписание интернета?","text":"«Телевизор» (00:00:5e:00:53:03): интернет выключается в 23:00 и включается в 07:00 (время роутера, Самара). Если сейчас как раз время «без интернета», он выключится сразу. Если это этот iPhone в домашнем Wi-Fi, приложение потеряет связь; вернуть — через мобильный интернет.","button":"Сохранить"}
"""#

    /// 428 observed.
    public static let confirmDiradd: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"4fda16916aec561bb8a0fca7a5ff4943","expires_in":60,"danger":"high","title":"Пускать ozon.ru напрямую?","text":"Сайт будет открываться без VPN на всех устройствах дома (MyDirect). VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Добавить"}
"""#

    /// 428 observed.
    public static let confirmDirdel: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"8eebacfeafe6e09e81db2b1bb73c127b","expires_in":60,"danger":"high","title":"Убрать kinopoisk.ru из MyDirect?","text":"Сайт снова пойдёт через VPN. VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Убрать"}
"""#

    /// 428 observed.
    public static let confirmSvcdirectOn: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"cc6d079f16c64282a56f165720951d1e","expires_in":60,"danger":"high","title":"Пускать YouTube напрямую?","text":"Сервис будет работать без VPN на всех устройствах дома (запись в MyDirect). VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Напрямую"}
"""#

    /// 428 observed.
    public static let confirmSvcdirectOff: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"e3d7dc648132288fb512224ae29e26bf","expires_in":60,"danger":"high","title":"Хайпиксель снова через VPN?","text":"Запись уберётся из MyDirect. VPN перезапустится, связь через VPN пропадёт на несколько секунд.","button":"Через VPN"}
"""#

    /// 428 observed.
    public static let confirmZapretOn: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"0db05c9f83ec319374ca426a686cea18","expires_in":60,"danger":"high","title":"Включить zapret для YouTube и Discord?","text":"YouTube и Discord пойдут напрямую через провайдера, с IP провайдера (не через VPN). Остальное не меняется. VPN перезапустится примерно на 5 секунд, открытые видео и звонки переподключатся.","button":"Включить"}
"""#

    /// 428 observed.
    public static let confirmZapretOff: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"6959661c82ce6f0e6c8255d60c21cd29","expires_in":60,"danger":"high","title":"Выключить zapret?","text":"YouTube и Discord снова пойдут через VPN. VPN перезапустится примерно на 5 секунд.","button":"Выключить"}
"""#

    /// 428 observed (medium).
    public static let confirmTgwsOn: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"e3c0b366beb44bc126d8f352f0c1e8f7","expires_in":60,"danger":"medium","title":"Включить прокси Telegram?","text":"Telegram на всех устройствах дома пойдёт через Cloudflare с IP провайдера, а не через VPN. Если прокси перестанет работать, Telegram сам вернётся на VPN. Режим экспериментальный.","button":"Включить"}
"""#

    /// 428 observed (medium).
    public static let confirmTgwsOff: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"9ef45488a67682cd7f7de587e0d0a172","expires_in":60,"danger":"medium","title":"Выключить прокси Telegram?","text":"Telegram снова пойдёт через VPN.","button":"Выключить"}
"""#

    /// 428 observed (critical).
    public static let confirmRevokeAll: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"7eab9862fb46a5d0e091a822cf99c41b","expires_in":60,"danger":"critical","title":"Выйти на всех устройствах?","text":"Доступ отзывается у всех телефонов с приложением, и у этого тоже. Войти заново — пароль и число в Telegram.","button":"Выйти везде"}
"""#

    /// 428 observed (critical, web:true).
    public static let confirmRevokeAllWeb: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"518a7f2c40f50edf1a650e872fb6cb70","expires_in":60,"danger":"critical","title":"Выйти на всех устройствах?","text":"Доступ отзывается у всех телефонов с приложением, и у этого тоже. Войти заново — пароль и число в Telegram. Также закроются все сессии веб-панели, и каждый браузер снова попросит код из Telegram.","button":"Выйти везде"}
"""#
}
