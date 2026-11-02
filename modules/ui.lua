local appUI = {}

function appUI.create(dependencies)
  local function drawAdminHeader()
    local sim = ac.getSim()
    if not dependencies.isAdminUnlocked() then return end

    ui.sameLine(ui.windowWidth() - 110)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.1, 0.45, 0.15, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.14, 0.55, 0.2, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.14, 0.55, 0.2, 1))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
    if ui.button('ADMIN MODE', vec2(100, 18)) then
      dependencies.lockAdmin()
    end
    if ui.itemHovered() and sim.isOnlineRace then
      ui.setTooltip('Click to lock race-control actions')
    end
    ui.popStyleColor(4)
  end

  local function drawAdminLoginPage()
    local state = dependencies.getLoginState()
    ui.newLine(3)
    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.yellow)
    ui.setNextTextBold()
    ui.text('SERVER ADMIN ACCESS')
    ui.popStyleColor()
    ui.separator()

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
    ui.textWrapped('Log in with the server admin password to open race-control tools and broadcast flag changes to the lobby.')
    ui.popStyleColor()
    ui.newLine(2)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('SERVER STATUS')
    ui.popStyleColor()
    ui.text(ac.getSim().isOnlineRace and 'Online session — server authentication required' or 'Offline session')
    ui.newLine(2)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('ADMIN PASSWORD')
    ui.popStyleColor()
    ui.setNextItemWidth(ui.availableSpaceX())
    local updatedPassword, _, enterPressed = ui.inputText(
      '##adminpw',
      state.password,
      bit.bor(ui.InputTextFlags.Password, ui.InputTextFlags.FocusByDefault)
    )
    dependencies.setLoginPassword(updatedPassword)

    if state.error ~= '' then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.danger)
      ui.textWrapped(state.error)
      ui.popStyleColor()
    elseif state.cooldown > 0 then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.text(string.format('Please wait %.0f seconds before trying again.', math.ceil(state.cooldown)))
      ui.popStyleColor()
    end

    ui.newLine(2)
    local canSubmit = state.cooldown <= 0 and not state.pending
    if not canSubmit then
      ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.25, 0.25, 0.25, 1))
      ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.25, 0.25, 0.25, 1))
      ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.25, 0.25, 0.25, 1))
      ui.pushStyleColor(ui.StyleColor.Text, rgbm(0.5, 0.5, 0.5, 1))
    end
    local buttonText = state.pending and 'VERIFYING…' or 'LOG IN'
    if ui.modernButton(buttonText, vec2(ui.availableSpaceX(), 40), ui.ButtonFlags.None, ui.Icons.ArrowRight) then
      if canSubmit then dependencies.attemptAdminLogin(updatedPassword) end
    end
    if enterPressed and canSubmit then dependencies.attemptAdminLogin(updatedPassword) end
    if not canSubmit then ui.popStyleColor(4) end

    if state.pending then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.text('Waiting for the server to confirm admin access…')
      ui.popStyleColor()
    end
  end

  return {
    drawAdminHeader = drawAdminHeader,
    drawAdminLoginPage = drawAdminLoginPage
  }
end

return appUI
