
--[[
@module dnsclient
@summary DNS域名解析
@version 1.0.0
@date    2024.04.10
@author  wendal
@tag LUAT_USE_NETWORK
@usage
-- LuatOS底层默认也带域名解析, 通常不需要使用这个库
-- 具体用法请查阅demo
]]

local dnsclient = {
    txid = 1
}

local function make_dns_query(txid, domain, txbuff)
    txbuff:seek(0)
    txbuff:pack("H", txid) -- 传输ID
    txbuff:write("\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00") -- 标志位
    local pos = 1
    domain = domain .. "."
    for i = 1, #domain, 1 do
        if domain:byte(i) == 0x2E then
            local n = i - pos
            txbuff:pack("bA", n, domain:sub(pos, i - 1))
            -- log.info("分解域名", n, domain:sub(pos, i - 1), domain:sub(pos, i-1))
            pos = i + 1
        end
        -- log.info("domain", domain:sub(i, 1))
    end
    -- txbuff:write(domain) -- 填充域名
    txbuff:write("\x00") -- 需要加个结尾
    txbuff:write("\x00\x01\0x00\x01") -- 填充类型和类
end

local function decode_dns_resp(rxbuff)
    local used = rxbuff:used()
    -- 前2个字节的TX ID,暂不校验
    if rxbuff[2] & 0x80 == 0 then
        log.warn("dns", "并非dns响应")
        return
    end
    if rxbuff[3] & 0x04 ~= 0 then
        log.warn("dns", "是dns响应,但有错误")
        return
    end
    -- 看看查询值是不是0x00 0x01
    if rxbuff[4] ~= 0x00 or rxbuff[5] ~= 0x01 then
        log.warn("dns", "是dns响应,但查询数量不是1,肯定非法")
        return
    end
    -- 普通响应有多少呢
    -- local Ns = rxbuff[8] * 256 + rxbuff[9]
    -- if Ns > 0 then
    --     log.info("dns", "有普通响应", Ns)
    -- end
    -- 先把域名解析出来
    local pos = 12
    local domain = ""
    while rxbuff[pos] ~= 0 do
        local n = rxbuff[pos]
        -- log.info("dns", "找到一段dns域名片段", n)
        domain = domain .. rxbuff:toStr(pos + 1, n) .. "."
        pos = pos + n + 1
    end
    domain = domain:sub(1, #domain - 1)
    -- log.info("dns", "解析域名", domain)
    pos = pos + 1 + 4 -- 跳过\0和后面的查询类型
    -- 响应有多少呢
    local ARRs = rxbuff[6] * 256 + rxbuff[7]
    if ARRs == 0 then
        log.info("dns", "有响应,但无结果", ARRs)
        return
    end
    local results = {}
    for i = 1, ARRs, 1 do
        -- log.info("dns", "第N条记录", i)
        -- 首先是域名
        local n = rxbuff[pos]
        -- log.info("dns", "域名的首段长度", string.format("%02X", n))
        if n & 0xC0 == 0xC0 then
            -- 属于引用长度, 支持解析, 否则就不支持解析咯
            pos = pos + 2
            -- 跳过TYPE和CLASS, 还有长度, 反正都一样
            local tp = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "TYPE", tp)
            pos = pos + 2
            local cl = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "CLASS", cl)
            pos = pos + 2
            local ttl = (rxbuff[pos] * 256 + rxbuff[pos+1]) * (256 * 256) + rxbuff[pos + 2] * 256 + rxbuff[pos+3]
            -- log.info("dns", "TTL", ttl)
            pos = pos + 4
            local len = rxbuff[pos] * 256 + rxbuff[pos+1]
            -- log.info("dns", "LEN", len)
            pos = pos + 2
            if len == 4 then
                -- 4字节IP
                local ip1,ip2,ip3,ip4 = rxbuff[pos], rxbuff[pos+1], rxbuff[pos+2], rxbuff[pos+3]
                local ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
                -- log.info("dns", "IP", ip)
                table.insert(results, {ip=ip, ttl=ttl})
                -- return {ip=ip,ttl=ttl}
            end
            pos = pos + len
        else
            log.info("dns", "出现了其他域名", "跳过解析")
        end
    end
    if dnsclient.opts.cached then
        dnsclient.caches[domain] = results
    end
    -- 发送一个消息
    sys.publish(dnsclient.opts.topic, domain, results)
end

local function netc_cb(sc, event)
    local rxbuff = dnsclient.rxbuff
    -- log.info("udp", sc, string.format("%08X", event))
    if event == socket.EVENT then
        rxbuff:seek(0)
        local ok = socket.rx(sc, rxbuff)
        if ok then
            -- log.info("remote_ip", remote_ip and remote_ip:toHex())
            -- if remote_ip and #remote_ip == 5 then
            --     local ip1,ip2,ip3,ip4 = remote_ip:byte(2),remote_ip:byte(3),remote_ip:byte(4),remote_ip:byte(5)
            --     remote_ip = string.format("%d.%d.%d.%d", ip1, ip2, ip3, ip4)
            -- else
            --     remote_ip = nil
            -- end
            -- log.info("socket", "读到数据", rxbuff:query():toHex(), remote_ip, remote_port)
            decode_dns_resp(rxbuff)
            rxbuff:del()
        else
            log.info("socket", "服务器断开了连接") -- 断网了?
            -- TODO 断网重连的问题
        end
    -- else
    --     log.info("udp", "其他事件")
    end
end

--[[
初始化DNS客户端
@api dnsclient.setup(opts)
@table 配置项, 可选
@return 成功返回true, 失败返回false
@usage
-- 初始化DNS客户端, 默认配置
dnsclient.setup()

-- 初始化DNS客户端, 指定服务器
dnsclient.setup({server="114.114.114.114"})

-- 初始化DNS客户端, 指定服务器和端口
dnsclient.setup({server="192.168.1.1", port=53})

-- 初始化DNS客户端, 缓存解析结果
dnsclient.setup({cached=true})

-- 初始化DNS客户端, 指定网络适配器
dnsclient.setup({adapter=socket.ETH0})
]]
function dnsclient.setup(opts)
    if not opts then
        opts = {}
    end
    if dnsclient.netc ~= nil then
        socket.close(dnsclient.netc)
        socket.release(dnsclient.netc)
    end
    dnsclient.netc = socket.create(opts.adapter, netc_cb)
    if dnsclient.netc == nil then
        return
    end
    if not opts.server then
        opts.server = "223.5.5.5"
    end
    if not opts.port then
        opts.port = 53
    end
    if not opts.topic then
        opts.topic = "dnsc_inc"
    end
    if not dnsclient.txbuff then
        dnsclient.txbuff = zbuff.create(1500)
    end
    if not dnsclient.rxbuff then
        dnsclient.rxbuff = zbuff.create(1500)
    end
    dnsclient.opts = opts
    dnsclient.caches = {}
    local result = socket.config(dnsclient.netc, nil, true)
    if not result then
        return
    end
    result = socket.connect(dnsclient.netc, opts.server, opts.port)
    if not result then
        return
    end
    return dnsclient.txbuff ~= nil and dnsclient.rxbuff ~= nil
end

function dnsclient.query(domain)
    make_dns_query(dnsclient.txid, domain, dnsclient.txbuff)
    dnsclient.txid = dnsclient.txid + 1
    if dnsclient.netc and dnsclient.txbuff:used() > 0 then
        return socket.tx(dnsclient.netc, dnsclient.txbuff)
    end
end

return dnsclient
