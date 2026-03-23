----------------------------------------------------------------------------------------
-- Chat message pipeline for RefineUI
----------------------------------------------------------------------------------------

local _, RefineUI = ...

local Chat = RefineUI:GetModule("Chat")
if not Chat then
    return
end

----------------------------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------------------------
function Chat:ShouldUseMessagePipeline(frame)
    return false
end

function Chat:InstallMessagePipeline()
    if self._messagePipelineInstalled then
        return
    end

    -- Blizzard must retain full ownership of chat message dispatch and storage.
    -- Hooking AddMessage or OnEvent is not secret-safe during encounter chat.
    self._messagePipelineInstalled = true
end
