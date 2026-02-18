local GT = GorilThreat
if not GT then
  return
end

SLASH_GORILTHREAT1 = "/gt"
SLASH_GORILTHREAT2 = "/gorilthreat"

SlashCmdList.GORILTHREAT = function(msg)
  GT:HandleSlash(msg or "")
end
