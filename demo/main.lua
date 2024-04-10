--[[
DNS客户端演示
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dnsdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

_G.sys = require("sys")
local dnsclient = require("dnsclient")

-- 统一联网函数
sys.taskInit(function()
    -- local device_id = mcu.unique_id():toHex()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成自动配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        -- device_id = wlan.getMac()
        wlan.connect(ssid, password, 1)
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2) -- 自动切换SIM卡
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        -- device_id = mobile.imei()
    elseif w5500 then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
    elseif socket then
        -- 适配的socket库也OK
        -- 没有其他操作, 单纯给个注释说明
    else
        -- 其他不认识的bsp, 循环提示一下吧
        while 1 do
            sys.wait(1000)
            log.info("bsp", "本bsp可能未适配网络层, 请查证")
        end
    end
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

function dns_result_cb(domain, results)
    log.info("dns查询结果", domain, json.encode(results))
end

sys.taskInit(function()
    sys.waitUntil("net_ready")
    sys.wait(100)
    dnsclient.setup()
    -- dnsclient.topic的默认值是dnsc_inc, 直接订阅也可以
    sys.subscribe("dnsc_inc", dns_result_cb)
    -- sys.subscribe(dnsclient.opts.topic, dns_result_cb)

    dnsclient.query("air32.cn")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("www.baidu.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("iot.openluat.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("air724ug.cn")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("aliyun.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("ntp.aliyun.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("www.google.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("github.com")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("gitee.com")
    sys.waitUntil("dnsc_inc", 500)

    -- 加几个肯定不合法的域名
    dnsclient.query("air.cnttt")
    sys.waitUntil("dnsc_inc", 500)

    dnsclient.query("zzz.cnzzz")
    sys.waitUntil("dnsc_inc", 500)

    log.info("全部结束")
end)

sys.run()
