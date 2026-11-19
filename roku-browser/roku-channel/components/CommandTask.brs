' Sends commands to the TV Browser server. Network calls are not allowed on
' the render thread, so they run here.

sub init()
    m.top.functionName = "taskLoop"
end sub

sub taskLoop()
    port = CreateObject("roMessagePort")
    m.top.observeField("request", port)
    m.top.ready = true
    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent" then
            req = msg.getData()
            if req <> invalid and req.base <> invalid then
                m.top.response = doRequest(req)
            end if
        end if
    end while
end sub

function doRequest(req as object) as object
    xfer = CreateObject("roUrlTransfer")
    query = ""
    for each key in req.params
        if query <> "" then query = query + "&"
        query = query + key + "=" + xfer.Escape(req.params[key])
    end for
    xfer.SetUrl(req.base + "/cmd?" + query)
    xfer.RetainBodyOnError(true)
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)

    result = { id: req.id, action: req.params.a, ok: false, body: "", error: "" }
    if not xfer.AsyncGetToString() then
        result.error = "request failed"
        return result
    end if

    ev = wait(30000, port)
    if type(ev) = "roUrlEvent" then
        code = ev.GetResponseCode()
        result.body = ev.GetString()
        if code = 200 then
            result.ok = true
        else if code < 0 then
            result.error = ev.GetFailureReason()
        else
            result.error = "HTTP " + code.ToStr()
        end if
    else
        xfer.AsyncCancel()
        result.error = "timed out"
    end if
    return result
end function
