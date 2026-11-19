' TV Browser: shows pages rendered by the server on your PC and turns
' Roku remote presses into mouse clicks, scrolling and typing.
'
' Remote controls:
'   Arrows       move the pointer (hold to speed up; at the top/bottom edge it scrolls)
'   OK           click
'   Back         go back a page (press twice on the first page to exit)
'   Rewind / FF  scroll up / down a screen
'   Play/Pause   toggle fast pointer
'   Replay       reload the page
'   * (Options)  menu: address bar, typing, zoom, server address

sub init()
    m.frames = [m.top.findNode("frameA"), m.top.findNode("frameB")]
    m.front = 0
    for each poster in m.frames
        poster.observeField("loadStatus", "onFrameLoad")
    end for

    m.placeholder = m.top.findNode("placeholder")
    m.cursor = m.top.findNode("cursor")
    m.busy = m.top.findNode("busy")
    m.statusBar = m.top.findNode("statusBar")
    m.statusLabel = m.top.findNode("statusLabel")
    m.menu = m.top.findNode("menu")
    m.menuList = m.top.findNode("menuList")

    m.holdTimer = m.top.findNode("holdTimer")
    m.holdTimer.observeField("fire", "onHoldTick")
    m.refreshTimer = m.top.findNode("refreshTimer")
    m.refreshTimer.observeField("fire", "onRefreshTick")
    m.statusTimer = m.top.findNode("statusTimer")
    m.statusTimer.observeField("fire", "hideStatus")
    m.exitTimer = m.top.findNode("exitTimer")
    m.exitTimer.observeField("fire", "disarmExit")

    m.menuActions = ["url", "type", "enter", "backspace", "tab", "reload", "forward", "home", "zoomIn", "zoomOut", "server"]
    menuTitles = ["Go to address / search", "Type text into page", "Press Enter", "Press Backspace", "Press Tab (next field)", "Reload page", "Forward", "Home page", "Zoom in (bigger text)", "Zoom out", "Change server address"]
    content = CreateObject("roSGNode", "ContentNode")
    for each title in menuTitles
        item = content.createChild("ContentNode")
        item.title = title
    end for
    m.menuList.content = content
    m.menuList.observeField("itemSelected", "onMenuSelect")

    m.cx = 640
    m.cy = 360
    updateCursor()
    m.fast = false
    m.holdKey = ""
    m.holdTicks = 0

    m.queue = []
    m.inFlight = false
    m.reqId = 0
    m.frameLoading = false
    m.frameDirty = false
    m.frameSeq = 0
    m.exitArmed = false
    m.currentUrl = ""
    m.dialogPurpose = ""
    m.connected = false

    m.task = CreateObject("roSGNode", "CommandTask")
    m.task.observeField("response", "onResponse")
    m.task.observeField("ready", "onTaskReady")
    m.taskReady = false
    m.task.control = "RUN"

    m.server = readServer()
    m.top.setFocus(true)
    if m.server = "" then
        askServer()
    else
        connect()
    end if
end sub

' ---------- server address ----------

function readServer() as string
    sec = CreateObject("roRegistrySection", "tvbrowser")
    if sec.Exists("server") then return sec.Read("server")
    return ""
end function

sub saveServer(address as string)
    sec = CreateObject("roRegistrySection", "tvbrowser")
    sec.Write("server", address)
    sec.Flush()
end sub

function cleanServer(text as string) as string
    s = text.Trim()
    s = s.Replace("http://", "").Replace("https://", "")
    while s.Len() > 0 and s.Right(1) = "/"
        s = s.Left(s.Len() - 1)
    end while
    if s <> "" and s.InStr(":") < 0 then s = s + ":8080"
    return s
end function

sub askServer()
    msg = "Start the TV Browser server on your computer, then type the address it prints, for example 192.168.1.20:8080"
    showKeyboard("Server address", msg, m.server, ["Save", "Cancel"], "server", false)
end sub

sub connect()
    m.connected = false
    m.placeholder.text = "Connecting to " + m.server + " ..."
    m.placeholder.visible = true
    m.queue = []
    send({ a: "state" })
    m.refreshTimer.control = "start"
end sub

' ---------- talking to the server ----------

sub onTaskReady()
    m.taskReady = m.task.ready
    pump()
end sub

sub send(params as object)
    last = m.queue.Peek()
    if params.a = "scroll" and last <> invalid and last.a = "scroll" then
        last.dy = last.dy + params.dy
        return
    end if
    m.queue.Push(params)
    pump()
end sub

sub pump()
    if m.inFlight or not m.taskReady or m.server = "" or m.queue.Count() = 0 then return
    params = m.queue.Shift()
    strParams = {}
    for each key in params
        strParams[key] = asStr(params[key])
    end for
    m.reqId = m.reqId + 1
    m.inFlight = true
    if params.a <> "scroll" and params.a <> "state" then m.busy.visible = true
    m.task.request = { id: m.reqId, base: "http://" + m.server, params: strParams }
end sub

function asStr(v as dynamic) as string
    t = type(v)
    if t = "String" or t = "roString" then return v
    if t = "Boolean" or t = "roBoolean" then
        if v then return "1"
        return "0"
    end if
    return Str(v).Trim()
end function

sub onResponse()
    r = m.task.response
    m.inFlight = false
    m.busy.visible = false
    data = invalid
    if r.body <> invalid and r.body <> "" then data = ParseJSON(r.body)

    if r.ok and data <> invalid then
        if not m.connected then
            m.connected = true
            showStatus("Arrows: move  |  OK: click  |  REW/FF: scroll  |  *: menu  |  Back: back")
        end if
        handleState(data, r.action)
        refreshFrame()
    else
        reason = r.error
        if data <> invalid and getStr(data, "error") <> "" then reason = getStr(data, "error")
        if not m.connected then
            m.placeholder.text = "Can't reach the server at " + m.server + " (" + reason + ")." + chr(10) + "Make sure it's running on your computer, then press * and choose Change server address."
            m.placeholder.visible = true
        else
            showStatus("Server problem: " + reason)
        end if
    end if
    pump()
end sub

sub handleState(s as object, action as string)
    m.currentUrl = getStr(s, "url")
    title = getStr(s, "title")
    err = getStr(s, "error")
    if err <> "" then
        showStatus(err)
    else if action = "back" and getBool(s, "wentBack") = false then
        m.exitArmed = true
        m.exitTimer.control = "start"
        showStatus("This is the first page. Press Back again to exit.")
    else if action = "zoom" and s.zoom <> invalid then
        showStatus("Zoom " + Str(Int(s.zoom * 100 + 0.5)).Trim() + "%")
    else if action = "nav" or action = "back" or action = "forward" or action = "home" or action = "reload" then
        showStatus(title + "   " + m.currentUrl)
    end if

    ' Clicking a text box opens the on-screen keyboard right away.
    if action = "click" and getBool(s, "editable") then
        showKeyboard("Type text", "Type into the field you clicked", getStr(s, "value"), ["Type + Enter", "Type", "Cancel"], "type", getBool(s, "password"))
    end if
end sub

function getStr(aa as object, key as string) as string
    v = aa[key]
    if v = invalid then return ""
    t = type(v)
    if t = "String" or t = "roString" then return v
    return ""
end function

function getBool(aa as object, key as string) as boolean
    v = aa[key]
    if v = invalid then return false
    t = type(v)
    if t = "Boolean" or t = "roBoolean" then return v
    return false
end function

' ---------- page image ----------

sub refreshFrame()
    if m.server = "" or not m.connected then return
    if m.frameLoading then
        m.frameDirty = true
        return
    end if
    m.frameLoading = true
    m.frameDirty = false
    m.frameSeq = m.frameSeq + 1
    m.frames[1 - m.front].uri = "http://" + m.server + "/frame.jpg?n=" + m.frameSeq.ToStr()
end sub

sub onFrameLoad(event as object)
    poster = event.getRoSGNode()
    status = event.getData()
    back = m.frames[1 - m.front]
    if not poster.isSameNode(back) then return
    if status = "ready" then
        back.visible = true
        m.frames[m.front].visible = false
        m.front = 1 - m.front
        m.placeholder.visible = false
        m.frameLoading = false
    else if status = "failed" then
        m.frameLoading = false
    else
        return
    end if
    if m.frameDirty then refreshFrame()
end sub

sub onRefreshTick()
    ' Picks up changes on the page (videos, animations, slow loads).
    if not m.inFlight and not m.menu.visible and m.queue.Count() = 0 then
        if m.connected then
            refreshFrame()
        else if m.server <> "" then
            send({ a: "state" })
        end if
    end if
end sub

' ---------- status bar ----------

sub showStatus(text as string)
    m.statusLabel.text = text
    m.statusBar.visible = true
    m.statusTimer.control = "stop"
    m.statusTimer.control = "start"
end sub

sub hideStatus()
    m.statusBar.visible = false
end sub

sub disarmExit()
    m.exitArmed = false
end sub

' ---------- pointer ----------

sub updateCursor()
    m.cursor.translation = [m.cx, m.cy]
end sub

sub startHold(key as string)
    m.holdKey = key
    m.holdTicks = 0
    moveCursor()
    m.holdTimer.control = "start"
end sub

sub stopHold()
    m.holdKey = ""
    m.holdTimer.control = "stop"
end sub

sub onHoldTick()
    if m.holdKey = "" then return
    m.holdTicks = m.holdTicks + 1
    if m.holdTicks < 5 then return ' short pause before repeating
    moveCursor()
end sub

sub moveCursor()
    stepSize = 14
    if m.fast then stepSize = 32
    boost = m.holdTicks
    if boost > 25 then boost = 25
    stepSize = stepSize + boost

    dx = 0
    dy = 0
    if m.holdKey = "up" then dy = -stepSize
    if m.holdKey = "down" then dy = stepSize
    if m.holdKey = "left" then dx = -stepSize
    if m.holdKey = "right" then dx = stepSize

    nx = m.cx + dx
    ny = m.cy + dy
    if nx < 0 then nx = 0
    if nx > 1279 then nx = 1279
    ' Pushing past the top or bottom edge scrolls the page.
    if ny < 0 then
        send({ a: "scroll", dy: -stepSize * 4, x: m.cx, y: 0 })
        ny = 0
    else if ny > 719 then
        send({ a: "scroll", dy: stepSize * 4, x: m.cx, y: 719 })
        ny = 719
    end if
    m.cx = nx
    m.cy = ny
    updateCursor()
end sub

' ---------- menu ----------

sub showMenu()
    stopHold()
    m.menu.visible = true
    m.menuList.jumpToItem = 0
    m.menuList.setFocus(true)
end sub

sub hideMenu()
    m.menu.visible = false
    m.top.setFocus(true)
end sub

sub onMenuSelect()
    action = m.menuActions[m.menuList.itemSelected]
    hideMenu()
    if action = "url" then
        showKeyboard("Go to address", "Type a web address (like weather.com) or words to search", m.currentUrl, ["Go", "Cancel"], "url", false)
    else if action = "type" then
        showKeyboard("Type text", "Text is typed into the field that is selected on the page", "", ["Type + Enter", "Type", "Cancel"], "type", false)
    else if action = "enter" then
        send({ a: "key", key: "Enter" })
    else if action = "backspace" then
        send({ a: "key", key: "Backspace" })
    else if action = "tab" then
        send({ a: "key", key: "Tab" })
    else if action = "reload" then
        send({ a: "reload" })
    else if action = "forward" then
        send({ a: "forward" })
    else if action = "home" then
        send({ a: "home" })
    else if action = "zoomIn" then
        send({ a: "zoom", step: "0.25" })
    else if action = "zoomOut" then
        send({ a: "zoom", step: "-0.25" })
    else if action = "server" then
        askServer()
    end if
end sub

' ---------- on-screen keyboard ----------

sub showKeyboard(title as string, message as string, text as string, buttons as object, purpose as string, secure as boolean)
    stopHold()
    dlg = CreateObject("roSGNode", "StandardKeyboardDialog")
    dlg.title = title
    dlg.message = [message]
    dlg.text = text
    dlg.buttons = buttons
    if secure then dlg.textEditBox.secureMode = true
    dlg.observeField("buttonSelected", "onDialogButton")
    dlg.observeField("wasClosed", "onDialogClosed")
    m.dialogPurpose = purpose
    m.top.dialog = dlg
end sub

sub onDialogButton(event as object)
    dlg = event.getRoSGNode()
    index = dlg.buttonSelected
    text = dlg.text
    purpose = m.dialogPurpose
    m.dialogPurpose = ""
    dlg.close = true
    m.top.setFocus(true)

    if purpose = "server" then
        address = cleanServer(text)
        if index = 0 and address <> "" then
            m.server = address
            saveServer(address)
            connect()
        else if m.server = "" then
            m.placeholder.text = "No server address set. Press * and choose Change server address."
        end if
    else if purpose = "url" then
        if index = 0 then send({ a: "nav", url: text })
    else if purpose = "type" then
        if index = 0 then send({ a: "fill", text: text, enter: "1" })
        if index = 1 then send({ a: "fill", text: text, enter: "0" })
    end if
end sub

sub onDialogClosed()
    m.dialogPurpose = ""
    m.top.setFocus(true)
end sub

' ---------- remote keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if m.menu.visible then
        if press and (key = "back" or key = "options") then hideMenu()
        return true
    end if

    if not press then
        if key = m.holdKey then stopHold()
        return true
    end if

    if key = "up" or key = "down" or key = "left" or key = "right" then
        startHold(key)
        return true
    else if key = "OK" then
        send({ a: "click", x: m.cx, y: m.cy })
        return true
    else if key = "back" then
        if m.exitArmed or not m.connected then return false ' lets Roku close the channel
        send({ a: "back" })
        return true
    else if key = "rewind" then
        send({ a: "scroll", dy: -560, x: m.cx, y: m.cy })
        return true
    else if key = "fastforward" then
        send({ a: "scroll", dy: 560, x: m.cx, y: m.cy })
        return true
    else if key = "play" then
        m.fast = not m.fast
        if m.fast then
            showStatus("Fast pointer on")
        else
            showStatus("Fast pointer off")
        end if
        return true
    else if key = "replay" then
        send({ a: "reload" })
        return true
    else if key = "options" then
        showMenu()
        return true
    end if
    return false
end function
