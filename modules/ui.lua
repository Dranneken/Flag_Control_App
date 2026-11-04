local appUI = {}

function appUI.create(dependencies)
  local function drawAdminHeader()
    if not dependencies.isAdminUnlocked() then return end

    local state = dependencies.getAdminState()
    if state.notice ~= '' then
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.textWrapped(state.notice)
      ui.popStyleColor()
    end

    ui.sameLine(ui.windowWidth() - 250)
    if ui.button('CHANGE PASSWORD', vec2(130, 18)) then
      dependencies.beginPasswordChange()
    end
    ui.sameLine(ui.windowWidth() - 110)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.1, 0.45, 0.15, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.14, 0.55, 0.2, 1))
    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(0.14, 0.55, 0.2, 1))
    ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 1, 1, 1))
    if ui.button('ADMIN MODE', vec2(100, 18)) then
      dependencies.lockAdmin()
    end
    if ui.itemHovered() then
      ui.setTooltip('Click to lock race-control actions')
    end
    ui.popStyleColor(4)
  end

  local function drawAdminAccessPage()
    local state = dependencies.getAdminState()
    ui.newLine(3)
    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.yellow)
    ui.setNextTextBold()
    ui.text(state.mode == 'setup' and 'LOCAL ADMIN SETUP' or 'LOCAL ADMIN LOGIN')
    ui.popStyleColor()
    ui.separator()

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
    ui.textWrapped('Local access requires an allowlisted Content Manager Steam profile and a Flag Control password. This does not authenticate remote lobby messages.')
    ui.popStyleColor()
    ui.newLine(2)

    if state.mode == 'blocked' then
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.danger)
      ui.textWrapped(state.blockedMessage)
      ui.popStyleColor()
      ui.newLine(2)
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.textWrapped('Add your 17-digit Steam profile ID to the allowlist file shown below, then reload Flag Control. Flag Control creates the file automatically if it is missing.')
      if state.allowlistPath then
        ui.textWrapped('Allowlist path: ' .. state.allowlistPath)
      end
      ui.popStyleColor()
      return
    end

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
    if state.mode == 'setup' then
      ui.textWrapped('Set a local password for this allowlisted profile. Use 9–128 bytes.')
    else
      ui.textWrapped('The local profile is allowlisted. Enter the Flag Control password to unlock race-control actions.')
    end
    if state.defaultPasswordActive then
      ui.textWrapped('Default password: adminpass. Change it after signing in.')
    end
    ui.popStyleColor()
    ui.newLine(2)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('ACCESS MODE')
    ui.popStyleColor()
    ui.text(state.mode == 'setup' and 'First-time password setup' or 'Password required each session')
    ui.newLine(2)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('LOCAL ADMIN PASSWORD')
    ui.popStyleColor()
    ui.setNextItemWidth(ui.availableSpaceX())
    local updatedPassword, _, enterPressed = ui.inputText(
      '##localadminpw',
      state.password,
      bit.bor(ui.InputTextFlags.Password, ui.InputTextFlags.FocusByDefault)
    )
    dependencies.setPassword(updatedPassword)

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
    local buttonText
    if state.pending then
      buttonText = 'VERIFYING…'
    elseif state.mode == 'setup' then
      buttonText = 'SET LOCAL PASSWORD'
    else
      buttonText = 'LOG IN'
    end
    if ui.modernButton(buttonText, vec2(ui.availableSpaceX(), 40), ui.ButtonFlags.None, ui.Icons.ArrowRight) then
      if canSubmit then
        if state.mode == 'setup' then
          dependencies.startSetup()
        else
          dependencies.startLogin()
        end
      end
    end
    if enterPressed and canSubmit then
      if state.mode == 'setup' then
        dependencies.startSetup()
      else
        dependencies.startLogin()
      end
    end
    if not canSubmit then ui.popStyleColor(4) end

    if state.pending then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.text(string.format('Checking password… %d%%', math.floor(state.progress * 100)))
      ui.popStyleColor()
    elseif not state.defaultPasswordActive and state.notice ~= '' then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.textWrapped(state.notice)
      ui.popStyleColor()
    end

    if state.mode == 'login' then
      ui.separator()
      local resetLabel = state.resetArmed and 'CONFIRM PASSWORD RESET' or 'RESET LOCAL PASSWORD'
      if ui.button(resetLabel, vec2(ui.availableSpaceX(), 24)) then
        dependencies.beginPasswordReset()
      end
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.textWrapped('Reset requires this profile to remain on the local allowlist.')
      ui.popStyleColor()
    end
  end

  local function drawPasswordChangePage()
    local state = dependencies.getAdminState()
    ui.newLine(3)
    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.yellow)
    ui.setNextTextBold()
    ui.text('CHANGE LOCAL ADMIN PASSWORD')
    ui.popStyleColor()
    ui.separator()
    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
    ui.textWrapped('Choose a new password between 9 and 128 bytes, then enter it again to confirm.')
    ui.popStyleColor()
    ui.newLine(2)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('NEW PASSWORD')
    ui.popStyleColor()
    ui.setNextItemWidth(ui.availableSpaceX())
    local newPassword = ui.inputText(
      '##newadminpw',
      state.newPassword,
      bit.bor(ui.InputTextFlags.Password, ui.InputTextFlags.FocusByDefault)
    )
    dependencies.setNewPassword(newPassword)

    ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.settingsText)
    ui.text('CONFIRM NEW PASSWORD')
    ui.popStyleColor()
    ui.setNextItemWidth(ui.availableSpaceX())
    local confirmation = ui.inputText(
      '##confirmadminpw',
      state.passwordConfirmation,
      ui.InputTextFlags.Password
    )
    dependencies.setPasswordConfirmation(confirmation)

    if state.error ~= '' then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.danger)
      ui.textWrapped(state.error)
      ui.popStyleColor()
    elseif state.pending then
      ui.newLine()
      ui.pushStyleColor(ui.StyleColor.Text, dependencies.colors.muted)
      ui.text(string.format('Updating password… %d%%', math.floor(state.progress * 100)))
      ui.popStyleColor()
    end

    ui.newLine(2)
    if state.pending then return end
    if ui.button('SAVE NEW PASSWORD', vec2(ui.availableSpaceX(), 32)) then
      dependencies.startPasswordChange()
    end
    if ui.button('CANCEL', vec2(ui.availableSpaceX(), 24)) then
      dependencies.cancelPasswordChange()
    end
  end

  return {
    drawAdminHeader = drawAdminHeader,
    drawAdminAccessPage = drawAdminAccessPage,
    drawPasswordChangePage = drawPasswordChangePage
  }
end

return appUI
