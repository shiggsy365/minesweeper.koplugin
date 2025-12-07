local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local Font = require("ui/font")
local Size = require("ui/size")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Button = require("ui/widget/button")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Minesweeper = WidgetContainer:extend{
    name = "minesweeper",
    is_doc_only = false,
}

local DIFFICULTY_MODES = {
    {name = "Easy", rows = 10, cols = 10},
    {name = "Medium", rows = 15, cols = 15},
    {name = "Hard", rows = 25, cols = 25},
    {name = "Intense", rows = 50, cols = 50},
}

local MinesweeperGame = InputContainer:extend{
    modal = true,
    viewport_rows = 15,
    viewport_cols = 15,
}

function MinesweeperGame:init()
    self.dimen = Geom:new{
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    
    -- Default to Easy mode
    self.current_mode = 1
    self:setDifficulty(self.current_mode)
    
    -- Calculate mine count (35% of total squares)
    self.mines = math.floor(self.rows * self.cols * 0.35)
    
    -- Reserve space for header
    local header_height = Size.item.height_default * 3 + Size.padding.large * 3
    
    -- Calculate cell size based on viewport, not full grid
    local viewport_rows = math.min(self.viewport_rows, self.rows)
    local viewport_cols = math.min(self.viewport_cols, self.cols)
    
    self.cell_size = math.min(
        math.floor((self.dimen.w - Size.padding.large * 4) / viewport_cols),
        math.floor((self.dimen.h - header_height - Size.padding.large * 4) / viewport_rows)
    )
    
    -- Viewport scroll position
    self.scroll_row = 0
    self.scroll_col = 0
    
    self:newGame()
    
    if Device:isTouchDevice() then
        self.ges_events.TapCell = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
        self.ges_events.HoldCell = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            }
        }
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
    end
    
    self:initUI()
end

function MinesweeperGame:setDifficulty(mode_index)
    local mode = DIFFICULTY_MODES[mode_index]
    self.rows = mode.rows
    self.cols = mode.cols
    self.current_mode = mode_index
end

function MinesweeperGame:newGame()
    self.board = {}
    self.revealed = {}
    self.flagged = {}
    self.game_over = false
    self.won = false
    self.flags_placed = 0
    self.cells_revealed = 0
    self.scroll_row = 0
    self.scroll_col = 0
    
    for i = 1, self.rows do
        self.board[i] = {}
        self.revealed[i] = {}
        self.flagged[i] = {}
        for j = 1, self.cols do
            self.board[i][j] = 0
            self.revealed[i][j] = false
            self.flagged[i][j] = false
        end
    end
    
    self:placeMines()
    self:calculateNumbers()
end

function MinesweeperGame:placeMines()
    local placed = 0
    while placed < self.mines do
        local row = math.random(1, self.rows)
        local col = math.random(1, self.cols)
        if self.board[row][col] ~= -1 then
            self.board[row][col] = -1
            placed = placed + 1
        end
    end
end

function MinesweeperGame:calculateNumbers()
    for i = 1, self.rows do
        for j = 1, self.cols do
            if self.board[i][j] ~= -1 then
                local count = 0
                for di = -1, 1 do
                    for dj = -1, 1 do
                        if not (di == 0 and dj == 0) then
                            local ni, nj = i + di, j + dj
                            if ni >= 1 and ni <= self.rows and nj >= 1 and nj <= self.cols then
                                if self.board[ni][nj] == -1 then
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
                self.board[i][j] = count
            end
        end
    end
end

function MinesweeperGame:revealCell(row, col)
    if self.game_over or self.revealed[row][col] or self.flagged[row][col] then
        return
    end
    
    self.revealed[row][col] = true
    self.cells_revealed = self.cells_revealed + 1
    
    if self.board[row][col] == -1 then
        self.game_over = true
        self:revealAll()
        UIManager:show(InfoMessage:new{
            text = _("Game Over! You hit a mine!"),
        })
    elseif self.board[row][col] == 0 then
        for di = -1, 1 do
            for dj = -1, 1 do
                if not (di == 0 and dj == 0) then
                    local ni, nj = row + di, col + dj
                    if ni >= 1 and ni <= self.rows and nj >= 1 and nj <= self.cols then
                        self:revealCell(ni, nj)
                    end
                end
            end
        end
    end
    
    if self.cells_revealed + self.mines == self.rows * self.cols and not self.game_over then
        self.game_over = true
        self.won = true
        UIManager:show(InfoMessage:new{
            text = _("Congratulations! You won!"),
        })
    end
    
    self:refreshUI()
end

function MinesweeperGame:toggleFlag(row, col)
    if self.game_over or self.revealed[row][col] then
        return
    end
    
    self.flagged[row][col] = not self.flagged[row][col]
    if self.flagged[row][col] then
        self.flags_placed = self.flags_placed + 1
    else
        self.flags_placed = self.flags_placed - 1
    end
    
    self:refreshUI()
end

function MinesweeperGame:revealAll()
    for i = 1, self.rows do
        for j = 1, self.cols do
            self.revealed[i][j] = true
        end
    end
end

function MinesweeperGame:getCellColor(row, col)
    if self.revealed[row][col] then
        if self.board[row][col] == -1 then
            return Blitbuffer.COLOR_DARK_GRAY
        else
            return Blitbuffer.COLOR_LIGHT_GRAY
        end
    else
        return Blitbuffer.COLOR_WHITE
    end
end

function MinesweeperGame:getCellText(row, col)
    if self.flagged[row][col] then
        return "F"
    elseif self.revealed[row][col] then
        if self.board[row][col] == -1 then
            return "M"
        elseif self.board[row][col] > 0 then
            return tostring(self.board[row][col])
        end
    end
    return ""
end

function MinesweeperGame:scroll(d_row, d_col)
    local new_scroll_row = self.scroll_row + d_row
    local new_scroll_col = self.scroll_col + d_col
    
    -- Clamp scroll position
    local max_scroll_row = math.max(0, self.rows - self.viewport_rows)
    local max_scroll_col = math.max(0, self.cols - self.viewport_cols)
    
    self.scroll_row = math.max(0, math.min(max_scroll_row, new_scroll_row))
    self.scroll_col = math.max(0, math.min(max_scroll_col, new_scroll_col))
    
    self:refreshUI()
end

function MinesweeperGame:initUI()
    local grid = VerticalGroup:new{
        align = "center",
    }
    
    self.cell_widgets = {}
    
    -- Determine actual viewport size
    local viewport_rows = math.min(self.viewport_rows, self.rows)
    local viewport_cols = math.min(self.viewport_cols, self.cols)
    
    for vi = 1, viewport_rows do
        local row_group = HorizontalGroup:new{}
        self.cell_widgets[vi] = {}
        
        for vj = 1, viewport_cols do
            local cell = FrameContainer:new{
                width = self.cell_size,
                height = self.cell_size,
                padding = 0,
                margin = 0,
                bordersize = Size.border.thin,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = Geom:new{
                        w = self.cell_size,
                        h = self.cell_size,
                    },
                    TextWidget:new{
                        text = "",
                        face = Font:getFace("cfont", math.floor(self.cell_size * 0.5)),
                    }
                }
            }
            
            self.cell_widgets[vi][vj] = cell
            table.insert(row_group, cell)
        end
        
        table.insert(grid, row_group)
    end
    
    -- Update grid with current data
    self:updateGrid()
    
    -- Status text
    local status_text = TextWidget:new{
        text = self:getStatusText(),
        face = Font:getFace("cfont", 14),
    }
    
    -- Difficulty mode buttons
    local mode_buttons = HorizontalGroup:new{
        align = "center",
    }
    
    for i, mode in ipairs(DIFFICULTY_MODES) do
        if i > 1 then
            table.insert(mode_buttons, HorizontalSpan:new{width = Size.span.horizontal_default})
        end
        
        table.insert(mode_buttons, Button:new{
            text = mode.name,
            padding = Size.padding.small,
            enabled = self.current_mode ~= i,
            callback = function()
                self:setDifficulty(i)
                self.mines = math.floor(self.rows * self.cols * 0.35)
                self:newGame()
                UIManager:close(self)
                UIManager:show(MinesweeperGame:new{})
            end,
        })
    end
    
    local mode_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = Size.item.height_default,
        },
        mode_buttons,
    }
    
    -- Control buttons
    local button_container = CenterContainer:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = Size.item.height_default,
        },
        HorizontalGroup:new{
            align = "center",
            Button:new{
                text = "^",
                padding = Size.padding.small,
                callback = function()
                    self:scroll(-3, 0)
                end,
            },
            HorizontalSpan:new{width = Size.span.horizontal_default},
            Button:new{
                text = "v",
                padding = Size.padding.small,
                callback = function()
                    self:scroll(3, 0)
                end,
            },
            HorizontalSpan:new{width = Size.span.horizontal_default},
            Button:new{
                text = "<",
                padding = Size.padding.small,
                callback = function()
                    self:scroll(0, -3)
                end,
            },
            HorizontalSpan:new{width = Size.span.horizontal_default},
            Button:new{
                text = ">",
                padding = Size.padding.small,
                callback = function()
                    self:scroll(0, 3)
                end,
            },
            HorizontalSpan:new{width = Size.span.horizontal_default},
            Button:new{
                text = _("New"),
                padding = Size.padding.small,
                callback = function()
                    self:newGame()
                    self:refreshUI()
                end,
            },
            HorizontalSpan:new{width = Size.span.horizontal_default},
            Button:new{
                text = _("Close"),
                padding = Size.padding.small,
                callback = function()
                    UIManager:close(self)
                end,
            },
        }
    }
    
    self.status_widget = status_text
    
    self[1] = CenterContainer:new{
        dimen = self.dimen,
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            padding = Size.padding.large,
            VerticalGroup:new{
                align = "center",
                mode_container,
                VerticalSpan:new{width = Size.span.vertical_default},
                button_container,
                VerticalSpan:new{width = Size.span.vertical_default},
                status_text,
                VerticalSpan:new{width = Size.span.vertical_default},
                grid,
            }
        }
    }
end

function MinesweeperGame:getStatusText()
    local mode_name = DIFFICULTY_MODES[self.current_mode].name
    return string.format(_("%s | Mines: %d | Flags: %d | View: %d,%d"), 
        mode_name, self.mines, self.flags_placed, self.scroll_row + 1, self.scroll_col + 1)
end

function MinesweeperGame:updateGrid()
    local viewport_rows = math.min(self.viewport_rows, self.rows)
    local viewport_cols = math.min(self.viewport_cols, self.cols)
    
    for vi = 1, viewport_rows do
        for vj = 1, viewport_cols do
            local actual_row = self.scroll_row + vi
            local actual_col = self.scroll_col + vj
            
            if actual_row <= self.rows and actual_col <= self.cols then
                local cell = self.cell_widgets[vi][vj]
                cell.background = self:getCellColor(actual_row, actual_col)
                cell[1][1].text = self:getCellText(actual_row, actual_col)
            end
        end
    end
end

function MinesweeperGame:refreshUI()
    self:updateGrid()
    self.status_widget.text = self:getStatusText()
    UIManager:setDirty(self, "ui")
end

function MinesweeperGame:getCellFromPosition(pos)
    local header_height = Size.item.height_default * 3 + Size.padding.large * 3 + Size.span.vertical_default * 3
    
    local viewport_rows = math.min(self.viewport_rows, self.rows)
    local viewport_cols = math.min(self.viewport_cols, self.cols)
    
    local grid_width = viewport_cols * self.cell_size
    local grid_height = viewport_rows * self.cell_size
    
    local grid_start_x = (self.dimen.w - grid_width) / 2
    local grid_start_y = (self.dimen.h - grid_height) / 2 + header_height / 2
    
    local rel_x = pos.x - grid_start_x
    local rel_y = pos.y - grid_start_y
    
    if rel_x < 0 or rel_y < 0 or rel_x >= grid_width or rel_y >= grid_height then
        return nil, nil
    end
    
    local viewport_col = math.floor(rel_x / self.cell_size) + 1
    local viewport_row = math.floor(rel_y / self.cell_size) + 1
    
    local actual_row = self.scroll_row + viewport_row
    local actual_col = self.scroll_col + viewport_col
    
    if actual_row >= 1 and actual_row <= self.rows and actual_col >= 1 and actual_col <= self.cols then
        return actual_row, actual_col
    end
    
    return nil, nil
end

function MinesweeperGame:onTapCell(arg, ges)
    local row, col = self:getCellFromPosition(ges.pos)
    if row and col then
        self:revealCell(row, col)
    end
    return true
end

function MinesweeperGame:onHoldCell(arg, ges)
    local row, col = self:getCellFromPosition(ges.pos)
    if row and col then
        self:toggleFlag(row, col)
    end
    return true
end

function MinesweeperGame:onSwipe(arg, ges)
    local direction = ges.direction
    if direction == "west" then
        self:scroll(0, 3)
    elseif direction == "east" then
        self:scroll(0, -3)
    elseif direction == "north" then
        self:scroll(3, 0)
    elseif direction == "south" then
        self:scroll(-3, 0)
    end
    return true
end

function MinesweeperGame:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function MinesweeperGame:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.dimen
    end)
end

function Minesweeper:init()
    self.ui.menu:registerToMainMenu(self)
end

function Minesweeper:addToMainMenu(menu_items)
    menu_items.minesweeper = {
        text = _("Minesweeper"),
        sorting_hint = "tools",
        callback = function()
            self:showGame()
        end,
    }
end

function Minesweeper:showGame()
    local game_widget = MinesweeperGame:new{}
    UIManager:show(game_widget)
end

return Minesweeper
