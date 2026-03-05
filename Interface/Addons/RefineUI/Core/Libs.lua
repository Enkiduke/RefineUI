----------------------------------------------------------------------------------------
-- RefineUI Libs
-- Description: Manages external library loading and access.
----------------------------------------------------------------------------------------

local _, RefineUI = ...

----------------------------------------------------------------------------------------
-- Lib Globals
----------------------------------------------------------------------------------------
local _G = _G
local LibStub = _G.LibStub

----------------------------------------------------------------------------------------
-- Library Loading
----------------------------------------------------------------------------------------
RefineUI.Libs = {}

-- Load Libraries
RefineUI.LSM = LibStub("LibSharedMedia-3.0", true)
RefineUI.CBH = LibStub("CallbackHandler-1.0", true)

-- Add references for easier access if needed
RefineUI.Libs.LSM = RefineUI.LSM
RefineUI.Libs.CBH = RefineUI.CBH
