// Generated from the stage 3 client contract §8 (fixtures). Reference time: `SampleJSON.now`.
// No real addresses, tokens or secrets: MACs/IPs are documentation ranges, ids and tokens are dummies.

/// Sample bodies for SwiftUI previews and tests.
public enum SampleJSON {
    /// 2026-10-13 14:16:00 Europe/Samara.
    public static let now: Int = 1791886560

    /// Contract §8.1: normal state.
    public static let statusNormal: String = #"""
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":48,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Rt5Vb8Nw","name":"fspiratDE","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"},{"id":"Pz1Yc4Ue","name":"🇳🇱 Нидерланды","ms":63,"group":"nosok"},{"id":"Wm6Tj2Gk","name":"🇫🇮 Финляндия","ms":0,"group":"nosok"}]},"log":["13.10 13:20 вручную -> Kq7Lm2Xp","13.10 13:40 перезапуск VPN"],"history":[[1791885900,52],[1791886200,48]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"sub":{"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800,"title":"nosok"},"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14,"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800}],"svc_direct":[],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/"],"svc":{"Kq7Lm2Xp":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"Hd3Fs9Qa":{"ts":1791884590,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":88},{"kind":"web","name":"Discord","host":"discord.com","vpn":95},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":102}]},"direct":{"ts":1791884410,"base":9,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0}]}},"svc_running":false,"speed":{"vpn":{"via":"vpn","ts":1791880000,"down":91234567,"up":40123456,"latency":38,"ip":"203.0.113.77","country":"NL","server":"Hetzner (Германия)","streams":4,"up_limited":false},"direct":null},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-51,"rate":866,"up":120394882,"dn":2349872311},{"name":"","ip":"192.168.1.40","mac":"00:00:5e:00:53:02","online":true,"band":"wired","up":10392,"dn":88123,"direct":true},{"name":"tv-living","ip":"192.168.1.51","mac":"00:00:5e:00:53:03","online":true,"band":"2g","signal":-68,"rate":72,"up":0,"dn":0,"sched":"2300-0700"},{"name":"old-laptop","ip":"192.168.1.77","mac":"00:00:5e:00:53:04","online":false,"up":0,"dn":0,"blocked":true}],"sys":{"cpu":7,"cores":2,"load":"0.21 0.17 0.15","mem_total":245632,"mem_avail":121840,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3460,"temp":null,"uptime":352812,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":61344,"net":{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}}}
"""#

    /// Contract §8.2: right after a reboot (ping/targets/sub null, empty lists).
    public static let statusAfterReboot: String = #"""
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":null,"log":[],"history":[],"targets":null,"sub":null,"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14}],"svc_direct":[],"target_list":[],"svc":{},"svc_running":false,"speed":{"vpn":null,"direct":null},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-55,"rate":780,"up":0,"dn":0}],"sys":{"cpu":38,"cores":2,"load":"1.10 0.40 0.15","mem_total":245632,"mem_avail":150212,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":812,"temp":null,"uptime":95,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":40120,"net":{"dev":"wan","rx":0,"tx":0,"rx_total":1048576,"tx_total":524288}}}
"""#

    /// Contract §8.3: VPN off, everything direct.
    public static let statusDirectMode: String = #"""
{"running":true,"split_active":true,"current":"_direct","ping":{"updated":1791886200,"current":"_direct","socks":true,"real":45,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":41,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"}]},"log":["13.10 14:00 вручную -> _direct"],"history":[[1791886200,45]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0}]},"sub":null,"subs":[],"svc_direct":[],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/"],"svc":{"direct":{"ts":1791884410,"base":9,"list":[]}},"svc_running":false,"speed":{"vpn":null,"direct":null},"devices":[],"sys":{"cpu":3,"cores":2,"load":"0.05 0.08 0.10","mem_total":245632,"mem_avail":130000,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3000,"temp":51,"uptime":3700,"model":"","fw":"OpenWrt 25.12.5","xray_rss":50000,"net":{"dev":"wan","rx":640000,"tx":0,"rx_total":10,"tx_total":20}}}
"""#

    /// Contract §8.4: VPN check failing (ping pre-dialog case).
    public static let statusVPNFailing: String = #"""
{"running":true,"split_active":true,"current":"Kq7Lm2Xp","ping":{"updated":1791886200,"current":"Kq7Lm2Xp","socks":true,"real":0,"nodes":[{"id":"Kq7Lm2Xp","name":"fspiratNL","ms":0,"group":"fspirat","own":true},{"id":"Hd3Fs9Qa","name":"🇩🇪 Германия","ms":57,"group":"nosok"}]},"log":["13.10 13:20 вручную -> Kq7Lm2Xp","13.10 13:40 перезапуск VPN"],"history":[[1791885900,52],[1791886200,48]],"targets":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"sub":{"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800,"title":"nosok"},"subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14,"ts":1791885600,"up":1288490188,"down":40802189312,"total":214748364800,"expire":1793404800}],"svc_direct":[],"target_list":["web|YouTube|https://www.youtube.com/generate_204","web|Discord|https://discord.com/api/v10/gateway","web|Telegram|https://api.telegram.org/"],"svc":{"Kq7Lm2Xp":{"ts":1791886205,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":61},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":74}]},"Hd3Fs9Qa":{"ts":1791884590,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":88},{"kind":"web","name":"Discord","host":"discord.com","vpn":95},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":102}]},"direct":{"ts":1791884410,"base":9,"list":[{"kind":"web","name":"YouTube","host":"www.youtube.com","vpn":0},{"kind":"web","name":"Discord","host":"discord.com","vpn":0},{"kind":"web","name":"Telegram","host":"api.telegram.org","vpn":0}]}},"svc_running":false,"speed":{"vpn":{"via":"vpn","ts":1791880000,"down":91234567,"up":40123456,"latency":38,"ip":"203.0.113.77","country":"NL","server":"Hetzner (Германия)","streams":4,"up_limited":false},"direct":null},"devices":[{"name":"iPhone","ip":"192.168.1.23","mac":"5a:00:5e:00:53:01","online":true,"band":"5g","signal":-51,"rate":866,"up":120394882,"dn":2349872311},{"name":"","ip":"192.168.1.40","mac":"00:00:5e:00:53:02","online":true,"band":"wired","up":10392,"dn":88123,"direct":true},{"name":"tv-living","ip":"192.168.1.51","mac":"00:00:5e:00:53:03","online":true,"band":"2g","signal":-68,"rate":72,"up":0,"dn":0,"sched":"2300-0700"},{"name":"old-laptop","ip":"192.168.1.77","mac":"00:00:5e:00:53:04","online":false,"up":0,"dn":0,"blocked":true}],"sys":{"cpu":7,"cores":2,"load":"0.21 0.17 0.15","mem_total":245632,"mem_avail":121840,"disk_total":89216,"disk_used":31544,"tmp_total":122816,"tmp_used":3460,"temp":null,"uptime":352812,"model":"Xiaomi Mi Router AX3000T","fw":"OpenWrt 25.12.5 r30123-abcdef0123","xray_rss":61344,"net":{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}}}
"""#

    /// Contract §8.5.
    public static let net: String = #"""
{"dev":"wan","rx":18734216,"tx":1203448,"rx_total":96385412736,"tx_total":7346121904}
"""#

    /// Contract §8.6.
    public static let ledOn: String = #"""
{"on":true,"items":[{"name":"blue:status","on":true},{"name":"yellow:status","on":false},{"name":"mt76-phy0","on":true},{"name":"mt76-phy1","on":true}]}
"""#

    /// Contract §8.6.
    public static let ledAbsent: String = #"""
{"absent":true}
"""#

    /// Contract §8.6.
    public static let ledsetOff: String = #"""
{"on":false,"items":[{"name":"blue:status","on":false},{"name":"yellow:status","on":false},{"name":"mt76-phy0","on":false},{"name":"mt76-phy1","on":false}]}
"""#

    /// Contract §8.7.
    public static let dataDay: String = #"""
{"now":1791886560,"range":"day","step":0,"points":[[1791886320,47],[1791886380,0],[1791886440,-1],[1791886500,52]],"stats":{"avg":50,"min":47,"max":52,"fails":1,"offline_min":1},"events":[[1791886200,"manual","Сервер выбран вручную: fspiratNL"],[1791883800,"restart","Перезапуск VPN"],[1791880000,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5e:00:53:02)"],[1791871200,"online","Роутер снова на связи (не было 6 мин)"],[1791870840,"offline","Роутер пропал со связи"],[1791850000,"router","MyDirect + gosuslugi.ru"]],"offline_since":null,"last_ok":1791886530,"names":{"5a:00:5e:00:53:01":"iPhone владельца"},"tpoints":{"YouTube":[[1791886205,61]],"Discord":[[1791886205,0]],"Telegram":[[1791886205,74]]},"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[734003200,28991029248]},"00:00:5e:00:53:02":{"d":[1048576,10485760],"m":[20971520,209715200]}},"speed":[[1791879000,"direct",286000000,95000000,6],[1791880000,"vpn",91234567,40123456,38]],"mtg":null,"site":{"luci":"https://router.fspirat.xyz/","bot":"FSRouter_bot","mtg":"","panels":["fspirat.xyz"]},"newdevs":[{"ts":1791880000,"mac":"00:00:5e:00:53:02"}]}
"""#

    /// Contract §8.8.
    public static let dataDayOffline: String = #"""
{"now":1791886560,"range":"day","step":0,"points":[[1791886320,47],[1791886380,0],[1791886440,-1],[1791886500,-1]],"stats":{"avg":50,"min":47,"max":52,"fails":1,"offline_min":1},"events":[[1791886200,"manual","Сервер выбран вручную: fspiratNL"],[1791883800,"restart","Перезапуск VPN"],[1791880000,"newdev","Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5e:00:53:02)"],[1791871200,"online","Роутер снова на связи (не было 6 мин)"],[1791870840,"offline","Роутер пропал со связи"],[1791850000,"router","MyDirect + gosuslugi.ru"]],"offline_since":1791885840,"last_ok":1791885780,"names":{"5a:00:5e:00:53:01":"iPhone владельца"},"tpoints":{"YouTube":[[1791886205,61]],"Discord":[[1791886205,0]],"Telegram":[[1791886205,74]]},"traffic":{"5a:00:5e:00:53:01":{"d":[52428800,1610612736],"m":[734003200,28991029248]},"00:00:5e:00:53:02":{"d":[1048576,10485760],"m":[20971520,209715200]}},"speed":[[1791879000,"direct",286000000,95000000,6],[1791880000,"vpn",91234567,40123456,38]],"mtg":null,"site":{"luci":"https://router.fspirat.xyz/","bot":"FSRouter_bot","mtg":"","panels":["fspirat.xyz"]},"newdevs":[{"ts":1791880000,"mac":"00:00:5e:00:53:02"}]}
"""#

    /// Contract §8.8.
    public static let dataDayEmpty: String = #"""
{"now":1791886560,"range":"day","step":0,"points":[],"stats":{"avg":null,"min":null,"max":null,"fails":0,"offline_min":0},"events":[],"offline_since":null,"last_ok":null,"names":{},"tpoints":{},"traffic":{},"speed":[],"mtg":null,"site":{"luci":"","bot":"","mtg":"","panels":[]},"newdevs":[]}
"""#

    /// Contract §8.9 (login_id replaced by a dummy).
    public static let loginStart: String = #"""
{"login_id":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","number":24,"expires_in":120,"poll_every":2}
"""#

    /// Contract §8.9.
    public static let pollPending: String = #"""
{"state":"pending","expires_in":118}
"""#

    /// Contract §8.9 (token replaced by a dummy, not a real token).
    public static let pollApproved: String = #"""
{"state":"approved","token":"fsr1_TestTokenTestTokenTestTokenTestTokenTestTok","device_id":"49139e3a1db5a6ac","expires":1799662560,"hard_expires":1823422560}
"""#

    /// Contract §8.9.
    public static let cancelOK: String = #"""
{"ok":true,"state":"cancelled"}
"""#

    /// Contract §8.9.
    public static let me: String = #"""
{"device":{"id":"49139e3a1db5a6ac","name":"iPhone владельца","created":1791886560,"expires":1799662560,"hard_expires":1823422560},"now":1791886560}
"""#

    /// Contract §8.9: the 14-day warning must show.
    public static let meExpiring: String = #"""
{"device":{"id":"49139e3a1db5a6ac","name":"iPhone владельца","created":1761300000,"expires":1792836000,"hard_expires":1792836000},"now":1791886560}
"""#

    /// Contract §2.11.
    public static let confirmRestart: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"79217acbd9c66e9e1af7693324516b75","expires_in":60,"danger":"high","title":"Перезапустить VPN?","text":"Связь через VPN пропадёт на несколько секунд.","button":"Перезапустить"}
"""#

    /// Contract §2.11.
    public static let confirmReboot: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"e9cd4613c347db5985111bd0d7e5e582","expires_in":60,"danger":"critical","title":"Перезагрузить роутер?","text":"Интернет дома пропадёт на 1–2 минуты, приложение на это время покажет «не на связи». Счётчики трафика устройств обнулятся.","button":"Перезагрузить"}
"""#

    /// Contract §2.11.
    public static let confirmUpdate: String = #"""
{"error":"confirm_required","message":"Нужно подтверждение.","confirm":"578388c3d9636f559228b700ad625185","expires_in":60,"danger":"high","title":"Обновить подписки VPN?","text":"Список серверов скачается заново (до 1–2 минут), потом VPN перезапустится — связь через VPN пропадёт на несколько секунд. Если текущего сервера в подписке больше нет, роутер сам выберет другой.","button":"Обновить"}
"""#

    /// Contract §8.10.
    public static let jobStart: String = #"""
{"job":"fbe9f93b0caf8a91","poll_every":3}
"""#

    /// Contract §8.10.
    public static let jobRunning: String = #"""
{"state":"running","action":"ping"}
"""#

    /// Contract §8.10.
    public static let jobErrorOffline: String = #"""
{"state":"error","action":"ping","http":502,"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}
"""#

    /// Contract §8.10.
    public static let jobErrorStuck: String = #"""
{"state":"error","action":"ping","http":500,"error":"server_error","message":"Ошибка на сервере — попробуй через минуту."}
"""#

    /// Contract §8.10: `job_done.json` = done + `statusNormal` as `result`.
    public static var jobDone: String {
        return #"{"state":"done","action":"ping","http":200,"result":"# + statusNormal + "}"
    }
}
