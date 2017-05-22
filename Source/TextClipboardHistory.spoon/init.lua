--- === TextClipboardHistory ===
---
--- Keep a history of the clipboard, only for text entries.
--- Originally based on https://github.com/VFS/.hammerspoon/blob/master/tools/clipboard.lua.
---
--- Download: [https://github.com/Hammerspoon/Spoons/raw/master/Spoons/TextClipboardHistory.spoon.zip](https://github.com/Hammerspoon/Spoons/raw/master/Spoons/TextClipboardHistory.spoon.zip)

local obj={}
obj.__index = obj

-- Metadata
obj.name = "TextClipboardHistory"
obj.version = "0.4"
obj.author = "Diego Zamboni <diego@zzamboni.org>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- TextClipboardHistory.frequency
--- Variable
--- Speed in seconds to check for clipboard changes. If you check too frequently, you will degrade performance, if you check sparsely you will loose copies. Defaults to 0.8.
obj.frequency = 0.8

--- TextClipboardHistory.hist_size
--- Variable
--- How many items to keep on history. Defaults to 100
obj.hist_size = 100

--- TextClipboardHistory.honor_ignoredidentifiers
--- Variable
--- If `true`, check the data identifiers set in the pasteboard and ignore entries which match those listed in `TextClipboardHistory.ignoredIdentifiers`. The list of identifiers comes from http://nspasteboard.org. Defaults to `true`
obj.honor_ignoredidentifiers = true

--- TextClipboardHistory.paste_on_select
--- Variable
--- Whether to auto-type the item when selecting it from the menu. Can be toggled on the fly from the chooser. Defaults to `false`.
obj.paste_on_select = false

--- TextClipboardHistory.logger
--- Variable
--- Logger object used within the Spoon. Can be accessed to set the default log level for the messages coming from the Spoon.
obj.logger = hs.logger.new('TextClipboardHistory')

--- TextClipboardHistory.ignoredIdentifiers
--- Variable
--- Types of clipboard entries to ignore, see http://nspasteboard.org. Code from https://github.com/asmagill/hammerspoon-config/blob/master/utils/_menus/newClipper.lua
obj.ignoredIdentifiers = {
   ["de.petermaurer.TransientPasteboardType"] = true, -- Transient : Textpander, TextExpander, Butler
   ["com.typeit4me.clipping"]                 = true, -- Transient : TypeIt4Me
   ["Pasteboard generator type"]              = true, -- Transient : Typinator
   ["com.agilebits.onepassword"]              = true, -- Confidential : 1Password
   ["org.nspasteboard.TransientType"]         = true, -- Universal, Transient
   ["org.nspasteboard.ConcealedType"]         = true, -- Universal, Concealed
   ["org.nspasteboard.AutoGeneratedType"]     = true, -- Universal, Automatic
}

--- TextClipboardHistory.deduplicate
--- Variable
--- Whether to remove duplicates from the list, keeping only the latest one. Defaults to `true`.
obj.deduplicate = true

--- TextClipboardHistory.show_in_menubar
--- Variable
--- Whether to show a menubar item to open the clipboard history. Defaults to `true`
obj.show_in_menubar = true

--- TextClipboardHistory.menubar_title
--- Variable
--- String to show in the menubar if `TextClipboardHistory.show_in_menubar` is `true`. Defaults to `"\u{1f4ce}"`, which is the [Unicode paperclip character](https://codepoints.net/U+1F4CE)
obj.menubar_title   = "\u{1f4ce}"

----------------------------------------------------------------------

-- Internal variable - Chooser/menu object
obj.selectorobj = nil
-- Internal variable - Cache for focused window to work around the current window losing focus after the chooser comes up
obj.prevFocusedWindow = nil

local pasteboard = require("hs.pasteboard") -- http://www.hammerspoon.org/docs/hs.pasteboard.html
local settings = require("hs.settings") -- http://www.hammerspoon.org/docs/hs.settings.html
local hashfn   = require("hs.hash").MD5

-- Keep track of last change counter
local last_change = nil;
-- Array to store the clipboard history
local clipboard_history = nil

-- Internal function - persist the current history so it survives across restarts
function _persistHistory()
   settings.set("TextClipboardHistory.items",clipboard_history)
end

--- TextClipboardHistory.togglePasteOnSelect()
--- Method
--- Toggle the value of `TextClipboardHistory.paste_on_select`
function obj:togglePasteOnSelect()
   self.paste_on_select = not self.paste_on_select
   hs.notify.show("TextClipboardHistory", "Paste-on-select is now " .. (self.paste_on_select and "enabled" or "disabled"), "")
end

-- Internal method - process the selected item from the chooser. An item may invoke special actions, defined in the `actions` variable.
function obj:_processSelectedItem(value)
   local actions = {
      none = function() end,
      clear = hs.fnutils.partial(self.clearAll, self),
      toggle_paste_on_select  = hs.fnutils.partial(self.togglePasteOnSelect, self),
   }
   if self.prevFocusedWindow ~= nil then
      self.prevFocusedWindow:focus()
   end
   if value and type(value) == "table" then
      if value.action and actions[value.action] then
         actions[value.action](value)
      elseif value.text then
         pasteboard.setContents(value.text)
         self:pasteboardToClipboard(value.text)
         if (self.paste_on_select) then
            hs.eventtap.keyStroke({"cmd"}, "v")
         end
      end
      last_change = pasteboard.changeCount()
   end
end

--- TextClipboardHistory.clearAll()
--- Method
--- Clears the clipboard and history
function obj:clearAll()
   pasteboard.clearContents()
   clipboard_history = {}
   _persistHistory()
   last_change = pasteboard.changeCount()
end

--- TextClipboardHistory.clearLastItem()
--- Method
--- Clears the last added to the history
function obj:clearLastItem()
   table.remove(clipboard_history, 1)
   _persistHistory()
   last_change = pasteboard.changeCount()
end

-- Internal method: deduplicate the given list, and restrict it to the history size limit
function obj:dedupe_and_resize(list)
   local res={}
   local hashes={}
   for i,v in ipairs(list) do
      if #res < self.hist_size then
         local hash=hashfn(v)
         if (not self.deduplicate) or (not hashes[hash]) then
            table.insert(res, v)
            hashes[hash]=true
         end
      end
   end
   return res
end

--- TextClipboardHistory.pasteboardToClipboard(item)
--- Method
--- Add the given string to the history
---
--- Parameters:
---  * item - string to add to the clipboard history
---
--- Returns:
---  * None
function obj:pasteboardToClipboard(item)
   table.insert(clipboard_history, 1, item)
   clipboard_history = self:dedupe_and_resize(clipboard_history)
   _persistHistory() -- updates the saved history
end

-- Internal function - fill in the chooser options, including the control options
function obj:_populateChooser()
   menuData = {}
   for k,v in pairs(clipboard_history) do
      if (type(v) == "string") then
         table.insert(menuData, {text=v, subText=""})
      end
   end
   if #menuData == 0 then
      table.insert(menuData, { text="",
                               subText="《Clipboard is empty》",
                               action = 'none',
                               image = hs.image.imageFromName('NSCaution')})
   else
      table.insert(menuData, { text="《Clear Clipboard History》",
                               action = 'clear',
                               image = hs.image.imageFromName('NSTrashFull') })
   end
   table.insert(menuData, {
                   text="《" .. (self.paste_on_select and "Disable" or "Enable") .. " Paste-on-select》",
                   action = 'toggle_paste_on_select',
                   image = (self.paste_on_select and hs.image.imageFromName('NSSwitchEnabledOn') or hs.image.imageFromName('NSSwitchEnabledOff'))
   })
   self.logger.df("Returning menuData = %s", hs.inspect(menuData))
   return menuData
end

-- Internal method: Verify whether the pasteboard contents matches one of the ignoredIdentifiers.
-- Code from https://github.com/asmagill/hammerspoon-config/blob/master/utils/_menus/newClipper.lua
function obj:shouldBeStored()
   local goAhead = true
   for i,v in ipairs(hs.pasteboard.pasteboardTypes()) do
      if self.ignoredIdentifiers[v] then
         goAhead = false
         break
      end
   end
   if goAhead then
      for i,v in ipairs(hs.pasteboard.contentTypes()) do
         if self.ignoredIdentifiers[v] then
            goAhead = false
            break
         end
      end
   end
   return goAhead
end

--- TextClipboardHistory:checkAndStorePasteboard()
--- Method
--- If the pasteboard has changed, we add the current item to our history and update the counter
function obj:checkAndStorePasteboard()
   now = pasteboard.changeCount()
   if (now > last_change) then
      if (not self.honor_ignoredidentifiers) or self:shouldBeStored() then
         current_clipboard = pasteboard.getContents()
         self.logger.df("current_clipboard = %s", tostring(current_clipboard))
         if (current_clipboard == nil) and (pasteboard.readImage() ~= nil) then
            self.logger.df("Images not yet supported - ignoring image contents in clipboard")
         elseif current_clipboard ~= nil then
            self.logger.df("Adding %s to clipboard history", current_clipboard)
            self:pasteboardToClipboard(current_clipboard)
         else
            self.logger.df("Ignoring nil clipboard content")
         end
      else
         self.logger.df("Ignoring pasteboard entry because it matches ignoredIdentifiers")
      end
      last_change = now
   end
end

--- TextClipboardHistory:start()
--- Method
--- Start the clipboard history collector
function obj:start()
   clipboard_history = self:dedupe_and_resize(settings.get("TextClipboardHistory.items") or {}) -- If no history is saved on the system, create an empty history
   last_change = pasteboard.changeCount() -- keeps track of how many times the pasteboard owner has changed // Indicates a new copy has been made
   self.selectorobj = hs.chooser.new(hs.fnutils.partial(self._processSelectedItem, self))
   self.selectorobj:choices(hs.fnutils.partial(self._populateChooser, self))

   --Checks for changes on the pasteboard. Is it possible to replace with eventtap?
   timer = hs.timer.new(self.frequency, hs.fnutils.partial(self.checkAndStorePasteboard, self))
   timer:start()
   if self.show_in_menubar then
      self.menubaritem = hs.menubar.new()
         :setTitle(obj.menubar_title)
         :setClickCallback(hs.fnutils.partial(self.toggleClipboard, self))
   end
end

--- TextClipboardHistory:showClipboard()
--- Method
--- Display the current clipboard list in a chooser
function obj:showClipboard()
   if self.selectorobj ~= nil then
      self.selectorobj:refreshChoicesCallback()
      self.prevFocusedWindow = hs.window.focusedWindow()
      self.selectorobj:show()
   else
      hs.notify.show("TextClipboardHistory not properly initialized", "Did you call TextClipboardHistory:start()?", "")
   end
end

--- TextClipboardHistory:toggleClipboard()
--- Method
--- Show/hide the clipboard list, depending on its current state
function obj:toggleClipboard()
   if self.selectorobj:isVisible() then
      self.selectorobj:hide()
   else
      self:showClipboard()
   end
end

--- TextClipboardHistory:bindHotkeys(mapping)
--- Method
--- Binds hotkeys for TextClipboardHistory
---
--- Parameters:
---  * mapping - A table containing hotkey objifier/key details for the following items:
---   * show_clipboard - Display the clipboard history chooser
---   * toggle_clipboard - Show/hide the clipboard history chooser
function obj:bindHotkeys(mapping)
   local def = {
      show_clipboard = hs.fnutils.partial(self.showClipboard, self),
      toggle_clipboard = hs.fnutils.partial(self.toggleClipboard, self),
   }
   hs.spoons.bindHotkeysToSpec(def, mapping)
end

return obj

