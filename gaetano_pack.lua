-- gaetano_pack.lua

-- atlases first
SMODS.Atlas{ key="GaetanoAtlas",      path="GaetanoAtlas.png",      px=71, py=95 }
SMODS.Atlas{ key="SuperGaetanoAtlas", path="SuperGaetanoAtlas.png", px=71, py=95 }

-- REMOVE the manual list loader entirely

local function load_dir(subdir)
  local modpath = SMODS.current_mod.path .. subdir
  if NFS and NFS.getDirectoryItems and NFS.getInfo(modpath) then
    local files = NFS.getDirectoryItems(modpath)
    for _, filename in pairs(files) do
      if string.sub(filename, -4) == ".lua" then
        assert(SMODS.load_file(subdir .. "/" .. filename))() -- loads each .lua once
      end
    end
  end
end

load_dir("jokers")
load_dir("backs")
