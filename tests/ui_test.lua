package.path = './?.lua;./?/init.lua;' .. package.path

local submittedPassword
local updatedPassword
local locked = false
local adminUnlocked = false
ac = {
  getSim = function () return { isOnlineRace = true } end
}
rgbm = function (r, g, b, a) return { r = r, g = g, b = b, a = a } end
vec2 = function (x, y) return { x = x, y = y } end
bit = { bor = function (a, b) return a + b end }

ui = {
  StyleColor = { Text = 1, Button = 2, ButtonHovered = 3, ButtonActive = 4 },
  InputTextFlags = { Password = 1, FocusByDefault = 2 },
  ButtonFlags = { None = 0 },
  Icons = { ArrowRight = 1 },
  newLine = function () end,
  pushStyleColor = function () end,
  setNextTextBold = function () end,
  text = function () end,
  popStyleColor = function () end,
  separator = function () end,
  textWrapped = function () end,
  setNextItemWidth = function () end,
  availableSpaceX = function () return 300 end,
  inputText = function () return 'typed-password', nil, true end,
  modernButton = function () return false end,
  sameLine = function () end,
  windowWidth = function () return 800 end,
  button = function () return true end,
  itemHovered = function () return false end,
  setTooltip = function () end
}

local adminUI = require('modules/ui').create({
  colors = { yellow = {}, settingsText = {}, muted = {}, danger = {} },
  isAdminUnlocked = function () return adminUnlocked end,
  getLoginState = function ()
    return { password = '', error = '', cooldown = 0, pending = false }
  end,
  setLoginPassword = function (password) updatedPassword = password end,
  attemptAdminLogin = function (password) submittedPassword = password end,
  lockAdmin = function () locked = true end
})

adminUI.drawAdminLoginPage()
assert(updatedPassword == 'typed-password')
assert(submittedPassword == 'typed-password')

adminUnlocked = true
adminUI.drawAdminHeader()
assert(locked)

print('UI module tests passed')
