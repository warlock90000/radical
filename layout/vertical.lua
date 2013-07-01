local setmetatable = setmetatable
local print,pairs = print,pairs
local unpack=unpack
local util      = require( "awful.util"       )
local button    = require( "awful.button"     )
local checkbox  = require( "radical.widgets.checkbox" )
local beautiful = require("beautiful")
local wibox     = require( "wibox" )
local color     = require( "gears.color"      )

local module = {}

local function left(data)
  if data._current_item._tmp_menu then
    data = data._current_item._tmp_menu
    data.items[1][1].selected = true
    return true,data
  end
end

local function right(data)
  if data.parent_geometry.is_menu then
    for k,v in ipairs(data.items) do
      if v[1]._tmp_menu == data or v[1].sub_menu_m == data then
        v[1].selected = true
      end
    end
    data.visible = false
    data = data.parent_geometry
    return true,data
  end
end

local function up(data)
  data.previous_item.selected = true
end

local function down(data)
  data.next_item.selected = true
end

function module:setup_key_hooks(data)
  data:add_key_hook({}, "Up"      , "press", up    )
  data:add_key_hook({}, "&"       , "press", up    )
  data:add_key_hook({}, "Down"    , "press", down  )
  data:add_key_hook({}, "KP_Enter", "press", down  )
  data:add_key_hook({}, "Left"    , "press", left  )
  data:add_key_hook({}, "\""      , "press", left  )
  data:add_key_hook({}, "Right"   , "press", right )
  data:add_key_hook({}, "#"       , "press", right )
end

--Get preferred item geometry
local function item_fit(data,item,...)
  local w, h = item._private_data._fit(...)
  return w, item._private_data.height or h
end

function module:setup_item(data,item,args)
    --Create the background
  item.widget = wibox.widget.background()
  data.item_style(data,item,false,false)
  item.widget:set_fg(item._private_data.fg)

  --Event handling
  item.widget:connect_signal("mouse::enter", function() item.selected = true end)
  item.widget:connect_signal("mouse::leave", function() item.selected = false end)
  data._internal.layout:add(item)
  local buttons = {}
  for i=1,10 do
    if args["button"..i] then
      buttons[#buttons+1] = button({},i,args["button"..i])
    end
  end
  if not buttons[3] then --Hide on right click
    buttons[#buttons+1] = button({},3,function()
      data.visible = false
      if data.parent_geometry and data.parent_geometry.is_menu then
        data.parent_geometry.visible = false
      end
    end)
  end

  --Be sure to always hide sub menus, even when data.visible is set manually
  data:connect_signal("visible::changed",function(_,vis)
    if data._tmp_menu and data.visible == false then
      data._tmp_menu.visible = false
    end
  end)
  data:connect_signal("parent_geometry::changed",function(_,vis)
    local fit_w,fit_h = data._internal.layout:fit()
    data.height = fit_h
    data.style(data)
  end)
  item.widget:buttons( util.table.join(unpack(buttons)))

  --Create the main item layout
  local l,la,lr = wibox.layout.fixed.horizontal(),wibox.layout.align.horizontal(),wibox.layout.fixed.horizontal()
  local m = wibox.layout.margin(la)
  m:set_margins (0)
  m:set_left  ( data.item_style.margins.LEFT   )
  m:set_right ( data.item_style.margins.RIGHT  )
  m:set_top   ( data.item_style.margins.TOP    )
  m:set_bottom( data.item_style.margins.BOTTOM )
  local text_w = wibox.widget.textbox()
  item._private_data._fit = wibox.widget.background.fit
  m.fit = function(...)
      if item.visible == false or item._filter_out == true then
        return 0,0
      end
      return data._internal.layout.item_fit(data,item,...)
  end

  if data.fkeys_prefix == true then
    local pref = wibox.widget.textbox()
    pref.draw = function(self,w, cr, width, height)
      cr:set_source(color(beautiful.fg_normal))
      cr:paint()
      wibox.widget.textbox.draw(self,w, cr, width, height)
    end
    pref:set_markup("<span fgcolor='".. beautiful.bg_normal .."'><tt><b>F11</b></tt></span>")
    l:add(pref)
    m:set_left  ( 0 )
  end

  if args.prefix_widget then
    l:add(args.prefix_widget)
  end

  local icon = wibox.widget.imagebox()
  if args.icon then
    icon:set_image(args.icon)
  end
  l:add(icon)
  l:add(text_w)
  if item._private_data.sub_menu_f or item._private_data.sub_menu_m then
    local subArrow  = wibox.widget.imagebox() --TODO, make global
    subArrow.fit = function(box, w, h) return subArrow._image:get_width(),item.height end
    subArrow:set_image( beautiful.menu_submenu_icon   )
    lr:add(subArrow)
    item.widget.fit = function(box,w,h,...)
      args.y = data.height-h-data.margins.top
      return wibox.widget.background.fit(box,w,h,...)
    end
  end
  if item.checkable then
    item._internal.get_map.checked = function()
      if type(item._private_data.checked) == "function" then
        return item._private_data.checked()
      else
        return item._private_data.checked
      end
    end
    local ck = wibox.widget.imagebox()
    ck:set_image(item.checked and checkbox.checked() or checkbox.unchecked())
    lr:add(ck)
    item._internal.set_map.checked = function (value)
      item._private_data.checked = value
      ck:set_image(item.checked and checkbox.checked() or checkbox.unchecked())
    end
  end
  if args.suffix_widget then
    lr:add(args.suffix_widget)
  end
  la:set_left(l)
  la:set_right(lr)
  item.widget:set_widget(m)
  local fit_w,fit_h = data._internal.layout:fit()
  data.width = fit_w
  data.height = fit_h
  data.style(data)
  item._internal.set_map.text = function (value)
    text_w:set_markup(value)
    if data.auto_resize then
      local fit_w,fit_h = text_w:fit(999,9999)
      local is_largest = item == data._internal.largest_item_w
      if not data._internal.largest_item_w_v or data._internal.largest_item_w_v < fit_w then
        data._internal.largest_item_w = item
        data._internal.largest_item_w_v = fit_w
      end
      --TODO find new largest is item is smaller
  --     if data._internal.largest_item_h_v < fit_h then
  --       data._internal.largest_item_h =item
  --       data._internal.largest_item_h_v = fit_h
  --     end
    end
  end
  item._internal.set_map.icon = function (value)
    icon:set_image(value)
  end
  item._internal.set_map.text(item._private_data.text)
end

local function new(data)
  local l,real_l = wibox.layout.fixed.vertical(),nil
  local filter_tb = nil
  if data.show_filter then
    real_l = wibox.layout.fixed.vertical()
    real_l:add(l)
    filter_tb = wibox.widget.textbox()
    local bg = wibox.widget.background()
    bg:set_bg(beautiful.bg_highlight)
    bg:set_widget(filter_tb)
    filter_tb:set_markup("<b>Filter:</b>")
    filter_tb.fit = function(tb,width,height)
      return width,data.item_height
    end
    data:connect_signal("filter_string::changed",function()
      filter_tb:set_markup("<b>Filter:</b> "..data.filter_string)
    end)
    real_l:add(bg)
  else
    real_l = l
  end
  real_l.fit = function(a1,a2,a3)
    local result,r2 = wibox.layout.fixed.fit(a1,99999,99999)
    local total = data._total_item_height
    if data.auto_resize and data._internal.largest_item_w then
      return data._internal.largest_item_w_v+100,(total and total > 0 and total or data.rowcount*data.item_height) + (filter_tb and data.item_height or 0)
    else
      return data.default_width, (total and total > 0 and total or data.rowcount*data.item_height) + (filter_tb and data.item_height or 0)
    end
  end
  real_l.add = function(real_l,item)
    return wibox.layout.fixed.add(l,item.widget)
  end
  real_l.item_fit = item_fit
  real_l.setup_key_hooks = module.setup_key_hooks
  real_l.setup_item = module.setup_item
  return real_l
end

return setmetatable(module, { __call = function(_, ...) return new(...) end })
-- kate: space-indent on; indent-width 2; replace-tabs on;
