 
return function(App)
    local U = App.Utils
    local track = App.track
    local ReplicatedStorage, LocalPlayer = U.ReplicatedStorage, U.LocalPlayer
    local UserInputService = game:GetService("UserInputService")

    local HUD = { Providers = {} }

    local ORDER = { "Traits", "Breathings", "Talents" }
    local FONT, FONT_BOLD = Enum.Font.GothamMedium, Enum.Font.GothamBold
    local WHITE = Color3.new(1, 1, 1)
    local THEME = {
        bg    = Color3.fromHex("#0b0506"),
        panel = Color3.fromHex("#1a0508"),
        line  = Color3.fromHex("#ff2a3d"),
        text  = Color3.fromHex("#f5e9e9"),
        dim   = Color3.fromHex("#9a7a7e"),
        bar   = Color3.fromRGB(45, 16, 20),
    }

    -- colores de rareza del juego (con respaldo)
    local RarityColors = {
        Common = Color3.fromHex("#ffffff"), Uncommon = Color3.fromHex("#00ff00"),
        Rare = Color3.fromHex("#009dff"), Epic = Color3.fromHex("#cc00ff"),
        Legendary = Color3.fromHex("#ff8000"), Mythical = Color3.fromHex("#9d00ff"),
        Secret = Color3.fromHex("#ff0000"), Exclusive = Color3.fromHex("#8000ff"),
    }
    local RarityGradients = {} -- [rareza] = ColorSequence (Secret no lleva gradient: rojo sólido)
    local SPIN_ICON = "rbxassetid://118578118384367"
    local LOCK_ICON = "rbxassetid://114129245250726"      -- slots bloqueados de Breathings
    local SLOT_LOCK_ICON = "rbxassetid://110072694518245" -- slot 2 bloqueado de Traits
    pcall(function()
        local C = require(ReplicatedStorage.Omni.Utils.Colors)
        for name, e in pairs(C.Rarities) do
            if type(e) == "table" and typeof(e.Color) == "Color3" then RarityColors[name] = e.Color end
            if type(e) == "table" and typeof(e.Gradient) == "ColorSequence" and name ~= "Secret" then
                RarityGradients[name] = e.Gradient
            end
        end
    end)
    local function rarityColor(r) return RarityColors[tostring(r)] or THEME.text end
    local function hex(c) return "#" .. c:ToHex() end

    -- datos del juego: iconos y rarezas
    local function sharedMod(name)
        local ok, m = pcall(function() return require(ReplicatedStorage.Omni.Shared[name]) end)
        return (ok and type(m) == "table") and m or {}
    end
    local TraitsMod, BreathMod = sharedMod("Traits"), sharedMod("Breathings")
    local WeaponsMod, FightersMod, ItemsMod = sharedMod("Weapons"), sharedMod("Fighters"), sharedMod("Items")
    local function entry(mod, name)
        local l = mod.List
        return (type(l) == "table" and name ~= nil) and l[name] or nil
    end
    local function field(mod, name, key)
        local e = entry(mod, name)
        return e and e[key] or nil
    end
    local function itemIcon(name) return field(ItemsMod, name, "Icon") end

    local function fmt(v)
        v = tonumber(v) or 0
        if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
        if v >= 1e5 then return math.floor(v / 1000) .. "K" end
        return tostring(math.floor(v))
    end

    -- firma de una tabla (para saber si cambio)
    local function ser(v)
        if type(v) ~= "table" then return tostring(v) end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. ser(v[k]) end
        return "{" .. table.concat(out, ",") .. "}"
    end

    -- se queda solo con algunas claves de cada elemento de una lista
    local function pick(list, keys)
        local out = {}
        for i, e in ipairs(list) do
            local t = {}
            for _, k in ipairs(keys) do t[k] = e[k] end
            out[i] = t
        end
        return out
    end

    -- Firma ESTRUCTURAL de cada panel: solo lo que obliga a reconstruir.
    -- Lo demas (numeros, ranks, traits de los slots, bloqueos...) se actualiza en sitio.
    local Sig = {
        Traits = function(d)
            return {
                fighter = d.fighter, slots = #d.slots, goals = d.goals,
                pity = pick(d.pity, { "name", "max", "fighter", "slot" }),
            }
        end,
        Talents = function(d)
            return { fighter = d.fighter, talents = pick(d.talents, { "name" }) }
        end,
        Breathings = function(d)
            return {
                weapon = d.weapon, slots = #d.slots, breathings = d.breathings, rarities = d.rarities,
                pity = d.pity and { name = d.pity.name, max = d.pity.max } or false,
            }
        end,
    }

    ---------------------------------------------------------------
    -- ScreenGui
    ---------------------------------------------------------------
    local function new(class, props, parent)
        local o = Instance.new(class)
        for k, v in pairs(props) do o[k] = v end
        if parent then o.Parent = parent end
        return o
    end
    local function corner(parent, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent) end

    local gui = new("ScreenGui", {
        Name = "AutoTraitsHUD", ResetOnSpawn = false, DisplayOrder = 50,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
    })
    if not pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end) then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    track({ Disconnect = function() pcall(function() gui:Destroy() end) end })

    local root = new("Frame", {
        Name = "Root", BackgroundColor3 = THEME.bg, BackgroundTransparency = 0.1,
        BorderSizePixel = 0, Position = UDim2.new(1, -284, 0, 80),
        Size = UDim2.fromOffset(272, 0), AutomaticSize = Enum.AutomaticSize.Y,
    }, gui)
    corner(root, 8)
    new("UIStroke", { Color = THEME.line, Thickness = 1, Transparency = 0.45 }, root)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8),
    }, root)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, root)

    local bar = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 0 }, root)
    local function label(parent, props)
        local t = new("TextLabel", {
            BackgroundTransparency = 1, Font = FONT, TextSize = 13, TextColor3 = THEME.text,
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "",
        }, parent)
        for k, v in pairs(props) do t[k] = v end
        return t
    end
    label(bar, { Size = UDim2.new(1, -16, 1, 0), Text = "G4B Hub", TextSize = 10, TextColor3 = THEME.dim })
    local closeBtn = new("TextButton", {
        BackgroundTransparency = 1, Font = FONT_BOLD, Text = "x", TextSize = 12,
        TextColor3 = THEME.line, Size = UDim2.fromOffset(14, 14), Position = UDim2.new(1, -14, 0, 0),
    }, bar)

    -- Gradient reutilizable: se crea una sola vez por instancia y despues solo se
    -- cambia su Color / Enabled (en vez de crear uno nuevo en cada actualizacion).
    local function applyGradient(inst, seq, rotation)
        local g = inst:FindFirstChild("RarityGradient")
        if seq then
            if not g then g = new("UIGradient", { Name = "RarityGradient" }, inst) end
            g.Color = seq
            g.Rotation = rotation or 0
            g.Enabled = true
        elseif g then
            g.Enabled = false
        end
    end

    -- pinta un TextLabel o UIStroke con el color/gradient de una rareza (Secret = rojo sólido)
    local function paint(inst, rarity)
        local seq = RarityGradients[rarity]
        local c = seq and WHITE or rarityColor(rarity)
        if inst:IsA("UIStroke") then inst.Color = c else inst.TextColor3 = c end
        applyGradient(inst, seq)
    end

    -- tine un ImageLabel con el gradient de la rareza (Secret = rojo solido)
    local function paintImage(img, rarity)
        local seq = RarityGradients[rarity]
        img.ImageColor3 = seq and WHITE or rarityColor(rarity)
        applyGradient(img, seq)
    end

    -- contenido con scroll: crece hasta MAX_H y a partir de ahi se desplaza
    local MAX_H = 340
    local content = new("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.line, LayoutOrder = 1,
    }, root)
    -- margen izquierdo: el ScrollingFrame recorta, sin esto se corta el borde de los iconos
    new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingTop = UDim.new(0, 3), PaddingRight = UDim.new(0, 8) }, content)
    local contentLayout = new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, content)
    local function fitContent()
        content.Size = UDim2.new(1, 0, 0, math.min(contentLayout.AbsoluteContentSize.Y, MAX_H))
    end
    track(contentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitContent))

    -- arrastrar desde la barra superior
    local dragging, dragStart, startPos
    local function isPointer(input)
        return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
    end
    track(bar.InputBegan:Connect(function(input)
        if isPointer(input) then dragging, dragStart, startPos = true, input.Position, root.Position end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if isPointer(input) then dragging = false end
    end))

    ---------------------------------------------------------------
    -- Piezas de dibujo
    ---------------------------------------------------------------
    local function addHeader(parent, order, title, icon)
        local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order }, parent)
        local x = 0
        if icon then
            new("ImageLabel", {
                BackgroundTransparency = 1, Image = icon, Size = UDim2.fromOffset(20, 20),
                Position = UDim2.new(0, 0, 0.5, -10),
            }, r)
            x = 26
        end
        label(r, { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(1, -x, 1, -2), Text = title, Font = FONT_BOLD, TextSize = 15 })
        new("Frame", {
            BackgroundColor3 = THEME.line, BackgroundTransparency = 0.55, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
        }, r)
    end

    -- fila: [icono o badge] texto ............ valor
    -- s.rarity: pinta el texto y el borde del icono con el color/gradient de esa rareza
    -- s.lock: agrega el icono de candado antes del valor
    -- s.valueGradient: el valor lleva gradient blanco -> ese color (vertical)
    --
    -- Devuelve un handle h con h.update(spec): cambia la fila EN SITIO (sin recrearla).
    -- Los hijos opcionales (icono, borde, badge, candado, valor) se crean la primera
    -- vez que hacen falta y despues solo se muestran/ocultan.
    local function addRow(parent, order, s)
        local r = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order }, parent)
        local img, stroke, badge, badgeLbl, lockImg, vl
        local tl = label(r, {})
        local h = { row = r }

        function h.update(sp)
            local useIcon = sp.icon ~= nil
            local useBadge = (not useIcon) and sp.badge ~= nil
            local x = 0

            if img then img.Visible = useIcon end
            if badge then badge.Visible = useBadge end

            if useIcon then
                if not img then
                    img = new("ImageLabel", {
                        BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20),
                        Position = UDim2.new(0, 0, 0.5, -10),
                    }, r)
                end
                img.Visible = true
                img.Image = sp.icon
                if sp.rarity then
                    if not stroke then
                        corner(img, 4)
                        stroke = new("UIStroke", { Thickness = 1.5 }, img)
                    end
                    stroke.Enabled = true
                    paintImage(img, sp.rarity)
                    paint(stroke, sp.rarity)
                else
                    if stroke then stroke.Enabled = false end
                    img.ImageColor3 = WHITE
                    applyGradient(img, nil)
                end
                x = 26
            elseif useBadge then
                if not badge then
                    badge = new("Frame", {
                        BorderSizePixel = 0, Size = UDim2.fromOffset(20, 20),
                        Position = UDim2.new(0, 0, 0.5, -10),
                    }, r)
                    corner(badge, 10)
                    badgeLbl = label(badge, {
                        Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
                        TextColor3 = Color3.new(0, 0, 0), TextSize = 12, Font = FONT_BOLD,
                    })
                end
                badge.Visible = true
                badge.BackgroundColor3 = sp.badge.color
                badgeLbl.Text = sp.badge.letter
                x = 26
            end

            local vw = sp.valueW or 0
            if sp.lock then
                if not lockImg then
                    lockImg = new("ImageLabel", {
                        BackgroundTransparency = 1, Image = LOCK_ICON, Size = UDim2.fromOffset(16, 16),
                    }, r)
                end
                lockImg.Position = UDim2.new(1, -vw - 20, 0.5, -8)
                lockImg.Visible = true
            elseif lockImg then
                lockImg.Visible = false
            end

            tl.Position = UDim2.fromOffset(x, 0)
            tl.Size = UDim2.new(1, -x - vw - (sp.lock and 20 or 0), 1, 0)
            tl.Text = sp.text or ""
            tl.TextColor3 = sp.textColor or THEME.text
            if sp.rarity then paint(tl, sp.rarity) else applyGradient(tl, nil) end

            if sp.value ~= nil then
                if not vl then
                    vl = label(r, {
                        Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Right, Font = FONT_BOLD,
                    })
                end
                vl.Visible = true
                vl.Text = tostring(sp.value)
                vl.TextColor3 = sp.valueColor or THEME.text
                if sp.valueGradient then
                    vl.TextColor3 = WHITE
                    applyGradient(vl, ColorSequence.new(WHITE, sp.valueGradient), 90)
                else
                    applyGradient(vl, nil)
                end
            elseif vl then
                vl.Visible = false
            end
        end

        h.update(s)
        return h
    end

    -- devuelve el relleno para poder cambiar su tamano despues
    local function addBar(parent, order, frac, color, rarity)
        local b = new("Frame", {
            BackgroundColor3 = THEME.bar, BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 4), LayoutOrder = order,
        }, parent)
        corner(b, 2)
        local f = new("Frame", {
            BackgroundColor3 = color, BorderSizePixel = 0,
            Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1),
        }, b)
        corner(f, 2)
        if rarity and RarityGradients[rarity] then
            f.BackgroundColor3 = WHITE
            new("UIGradient", { Color = RarityGradients[rarity] }, f)
        end
        return f
    end

    -- estadisticas en filas (una por linea, como en los paragraph). Devuelve update(stats)
    local function statSpec(s)
        local icon = (s.icon == "spin" and SPIN_ICON) or (s.item and itemIcon(s.item)) or nil
        return {
            icon = icon, text = s.label, textColor = THEME.dim,
            value = fmt(s.value), valueW = 70,
        }
    end

    local function addStats(parent, o, stats)
        local rows = {}
        for i, s in ipairs(stats) do rows[i] = addRow(parent, o(), statSpec(s)) end
        return function(newStats)
            for i, s in ipairs(newStats) do
                if rows[i] then rows[i].update(statSpec(s)) end
            end
        end
    end

    -- fila de iconos con borde del color de la rareza
    local function addIconGrid(parent, order, items)
        local g = new("Frame", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order,
        }, parent)
        new("UIGridLayout", {
            CellSize = UDim2.fromOffset(20, 20), CellPadding = UDim2.fromOffset(5, 5),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, g)
        for i, it in ipairs(items) do
            local c = new("Frame", { BackgroundColor3 = THEME.panel, BorderSizePixel = 0, LayoutOrder = i }, g)
            corner(c, 4)
            local stroke = new("UIStroke", { Color = it.color or THEME.text, Thickness = 1.5 }, c)
            if it.rarity then paint(stroke, it.rarity) end
            if it.icon then
                local img = new("ImageLabel", {
                    BackgroundTransparency = 1, Image = it.icon, Size = UDim2.fromOffset(20, 20),
                }, c)
                corner(img, 4)
                if it.rarity then paintImage(img, it.rarity) end
            else
                label(c, {
                    Size = UDim2.fromScale(1, 1), Text = tostring(it.letter or "?"),
                    TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = it.color, Font = FONT_BOLD,
                })
            end
        end
    end

    local function addNote(parent, order, text, color, rich)
        label(parent, {
            Size = UDim2.new(1, 0, 0, 16), LayoutOrder = order, Text = text,
            TextColor3 = color or THEME.dim, TextSize = 12, RichText = rich == true,
        })
    end

    local function fighterRow(parent, order, f)
        if not f then
            return addRow(parent, order, { badge = { letter = "?", color = THEME.dim }, text = "No fighter", textColor = THEME.dim })
        end
        local short = "[" .. tostring(f.id):sub(1, 6) .. "]"
        if not f.name then
            return addRow(parent, order, {
                badge = { letter = "!", color = Color3.fromRGB(255, 70, 70) }, text = "Invalid ID",
                textColor = Color3.fromRGB(255, 120, 120), value = short, valueColor = THEME.dim, valueW = 56,
            })
        end
        local color = rarityColor(field(FightersMod, f.name, "Rarity"))
        return addRow(parent, order, {
            badge = { letter = f.name:sub(1, 1):upper(), color = color },
            text = f.name, textColor = color, value = short, valueColor = THEME.dim, valueW = 56,
        })
    end

    -- fila de pity + barra. Devuelve update(pity)
    local function pityRows(parent, o, p, icon, color, rarity)
        local function spec(q)
            return {
                icon = icon, text = q.name, textColor = color, rarity = rarity,
                value = q.max and (fmt(q.value) .. "/" .. fmt(q.max)) or fmt(q.value), valueW = 90,
            }
        end
        local row = addRow(parent, o(), spec(p))
        local fill
        if p.max and p.max > 0 then fill = addBar(parent, o(), p.value / p.max, color, rarity) end
        return function(q)
            row.update(spec(q))
            if fill and q.max and q.max > 0 then
                fill.Size = UDim2.fromScale(math.clamp(q.value / q.max, 0, 1), 1)
            end
        end
    end

    ---------------------------------------------------------------
    -- Paneles
    -- Cada renderer dibuja el panel y DEVUELVE una funcion update(d) que
    -- refresca solo lo que cambia con los datos nuevos.
    ---------------------------------------------------------------
    local Renderers = {}

    -- ===== Traits =====
    local function traitSlotSpec(s)
        if s.locked then
            return { icon = SLOT_LOCK_ICON, text = "Locked", textColor = THEME.dim, value = s.label, valueColor = THEME.dim, valueW = 30 }
        elseif s.name then
            return {
                icon = field(TraitsMod, s.name, "Icon"), text = s.name,
                rarity = field(TraitsMod, s.name, "Rarity"),
                value = s.label, valueColor = THEME.dim, valueW = 30,
            }
        end
        return { text = "-", textColor = THEME.dim, value = s.label, valueColor = THEME.dim, valueW = 30 }
    end

    function Renderers.Traits(p, d)
        local o = 0
        local function n() o += 1 return o end
        addHeader(p, n(), "Auto Traits", TraitsMod.Icon)
        local updStats = addStats(p, n, d.stats)
        fighterRow(p, n(), d.fighter)

        local slotRows = {}
        for i, s in ipairs(d.slots) do
            slotRows[i] = addRow(p, n(), traitSlotSpec(s))
        end

        addNote(p, n(), "Goal")
        if #d.goals > 0 then
            local items = {}
            for _, name in ipairs(d.goals) do
                items[#items + 1] = {
                    icon = field(TraitsMod, name, "Icon"), letter = name:sub(1, 1),
                    rarity = field(TraitsMod, name, "Rarity"),
                }
            end
            addIconGrid(p, n(), items)
        else
            addNote(p, n(), "-")
        end

        addNote(p, n(), "Pity")
        local updPity = {}
        for i, pt in ipairs(d.pity) do
            local rar = field(TraitsMod, pt.name, "Rarity")
            updPity[i] = pityRows(p, n, pt, field(TraitsMod, pt.name, "Icon"), rarityColor(rar), rar)
            if pt.fighter then
                addNote(p, n(), "-> " .. pt.fighter .. (pt.slot and ("  " .. pt.slot) or ""))
            end
        end

        return function(nd)
            updStats(nd.stats)
            for i, s in ipairs(nd.slots) do
                if slotRows[i] then slotRows[i].update(traitSlotSpec(s)) end
            end
            for i, pt in ipairs(nd.pity) do
                if updPity[i] then updPity[i](pt) end
            end
        end
    end

    -- ===== Talents =====
    -- El gradient va en el RANK, no en el talent: blanco -> color del rank, vertical.
    -- Sin rank: gris solido (#8A8A8A) y texto "-".
    local TALENT_GRAY = Color3.fromHex("#8A8A8A")

    local function talentSpec(t)
        local on = t.goal ~= "OFF"
        return {
            text = t.name .. (on and ("  -> " .. t.goal) or "  (OFF)"),
            textColor = on and THEME.text or THEME.dim,
            lock = t.locked, valueW = 40,
            value = t.rank, valueColor = TALENT_GRAY, valueGradient = t.color,
        }
    end

    function Renderers.Talents(p, d)
        local o = 0
        local function n() o += 1 return o end
        addHeader(p, n(), "Auto Talents", nil)
        local updStats = addStats(p, n, d.stats)
        fighterRow(p, n(), d.fighter)

        local rows = {}
        for i, t in ipairs(d.talents) do
            rows[i] = addRow(p, n(), talentSpec(t))
        end

        return function(nd)
            updStats(nd.stats)
            for i, t in ipairs(nd.talents) do
                if rows[i] then rows[i].update(talentSpec(t)) end
            end
        end
    end

    -- ===== Breathings =====
    local function breathSlotSpec(s)
        local color = rarityColor(s.rarity)
        return {
            icon = field(BreathMod, s.name, "Icon"),
            text = s.name, textColor = color, lock = s.locked,
            value = s.rarity, valueColor = color, valueW = 70,
        }
    end

    function Renderers.Breathings(p, d)
        local o = 0
        local function n() o += 1 return o end
        addHeader(p, n(), "Auto Breathings", BreathMod.Icon)
        local updStats = addStats(p, n, d.stats)

        if d.weapon then
            local w = d.weapon
            local short = "[" .. tostring(w.id):sub(1, 6) .. "]"
            if w.name then
                local color = rarityColor(field(WeaponsMod, w.name, "Rarity"))
                addRow(p, n(), {
                    icon = field(WeaponsMod, w.name, "Icon"), text = w.name, textColor = color,
                    value = short, valueColor = THEME.dim, valueW = 56,
                })
            else
                addRow(p, n(), {
                    badge = { letter = "!", color = Color3.fromRGB(255, 70, 70) }, text = "Invalid ID",
                    textColor = Color3.fromRGB(255, 120, 120), value = short, valueColor = THEME.dim, valueW = 56,
                })
            end
        else
            addRow(p, n(), { badge = { letter = "?", color = THEME.dim }, text = "No weapon", textColor = THEME.dim })
        end

        local slotRows = {}
        for i, s in ipairs(d.slots) do
            slotRows[i] = addRow(p, n(), breathSlotSpec(s))
        end

        addNote(p, n(), "Goal")
        if #d.breathings > 0 then
            local items = {}
            for _, name in ipairs(d.breathings) do
                items[#items + 1] = { icon = field(BreathMod, name, "Icon"), letter = name:sub(1, 1), color = THEME.text }
            end
            addIconGrid(p, n(), items)
            local parts = {}
            for _, r in ipairs(d.rarities) do
                parts[#parts + 1] = '<font color="' .. hex(rarityColor(r)) .. '">' .. r .. "</font>"
            end
            addNote(p, n(), table.concat(parts, "  "), THEME.text, true)
        else
            addNote(p, n(), "-")
        end

        local updPity
        if d.pity then
            addNote(p, n(), "Pity")
            updPity = pityRows(p, n, d.pity, nil, rarityColor(d.pity.name))
        end

        return function(nd)
            updStats(nd.stats)
            for i, s in ipairs(nd.slots) do
                if slotRows[i] then slotRows[i].update(breathSlotSpec(s)) end
            end
            if updPity and nd.pity then updPity(nd.pity) end
        end
    end

    ---------------------------------------------------------------
    -- API
    ---------------------------------------------------------------
    local panels, open = {}, {} -- open[kind] = true si su panel esta pedido

    function HUD.Register(kind, provider) HUD.Providers[kind] = provider end

    local function rebuild(kind, p, d)
        p.update = nil
        for _, c in ipairs(p.frame:GetChildren()) do
            if not c:IsA("UIListLayout") then c:Destroy() end
        end
        local ok, res = pcall(Renderers[kind], p.frame, d)
        if ok then
            p.update = type(res) == "function" and res or nil
        else
            warn("[AutoTraits] HUD:", res)
        end
    end

    function HUD.Refresh()
        for kind, p in pairs(panels) do
            local provider = HUD.Providers[kind]
            if provider then
                local ok, d = pcall(provider.data)
                if ok and type(d) == "table" then
                    local full = ser(d)
                    -- nada cambio: no se toca ninguna instancia
                    if full ~= p.full then
                        p.full = full

                        local sig = full
                        local sigFn = Sig[kind]
                        if sigFn then
                            local sok, s = pcall(function() return ser(sigFn(d)) end)
                            if sok then sig = s end
                        end

                        if sig ~= p.sig or not p.update then
                            -- cambio la estructura: se reconstruye (poco frecuente)
                            p.sig = sig
                            rebuild(kind, p, d)
                        else
                            -- solo cambiaron valores: se actualizan las instancias existentes
                            local uok, err = pcall(p.update, d)
                            if not uok then
                                warn("[AutoTraits] HUD update:", err)
                                p.sig = nil -- fuerza reconstruir en el proximo cambio
                            end
                        end
                    end
                end
            end
        end
    end

    local function hide()
        gui.Enabled = false
        open = {}
    end
    track(closeBtn.Activated:Connect(hide))

    local function show(list)
        for _, c in ipairs(content:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        panels = {}
        for i, kind in ipairs(list) do
            local f = new("Frame", {
                BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i,
            }, content)
            new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, f)
            panels[kind] = { frame = f }
        end
        gui.Enabled = true
        HUD.Refresh()
    end

    -- Boton Show HUD de un paragraph: abre o cierra solo el panel de `kind`.
    function HUD.Toggle(kind)
        open[kind] = not open[kind] or nil
        local list = {}
        for _, k in ipairs(ORDER) do
            if open[k] then list[#list + 1] = k end
        end
        if #list == 0 then hide() else show(list) end
    end

    task.spawn(function()
        while App.alive do
            if gui.Enabled then pcall(HUD.Refresh) end
            task.wait(0.5)
        end
    end)

    return HUD
end
