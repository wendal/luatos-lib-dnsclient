# luatos-lib-dnsclient

DNS客户端,纯lua实现, 支持域名解析

## 介绍

虽然luatos底层也支持dns解析, 但有时需要测试其他dns服务器,这个库就提供了dns解析功能

## 安装

本协议库使用纯lua编写, 所以不需要编译, 直接将源码拷贝到项目即可

## 使用

```lua
local dnsclient = require("dnsclient")

sys.subscribe("dnsc_inc", function(domain, results)
    log.info("dns结果", domain, json.encode(results))
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(100)
    dnsclient.setup()
    dnsclient.query("air32.cn")
    sys.wait(500)
end)
```

## 变更日志

[changelog](changelog.md)

## LIcense

[MIT License](https://opensource.org/licenses/MIT)
