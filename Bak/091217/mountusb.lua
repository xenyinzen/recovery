#!/usr/bin/lua

local rootdir = "/root"
local udisk_dir = rootdir.."/udisk/"

function FindAndMountUDisk()
	local part

	part = "/dev/sda1"
	local ret = os.execute( "mount -o ro "..part.." "..udisk_dir )
	if ret ~= 0 then
		part = "/dev/sda"
		ret = os.execute( "mount -o ro "..part.." "..udisk_dir )
		if ret ~= 0 then 
			part = "/dev/sdb1"			
			ret = os.execute( "mount -o ro "..part.." "..udisk_dir )
			if ret ~= 0 then
				part = "/dev/sdb"
				ret = os.execute( "mount -o ro "..part.." "..udisk_dir )
				if ret ~= 0 then
					print("mount udisk failed."); 
					return -1 
				end			
			end	
		end
		
	end

	return 0
end

--
-- find U disk, mount it, and copy essential files into inner disk
--
os.execute("sleep 10")
os.execute("mkdir  -p "..udisk_dir)
ret = FindAndMountUDisk()
if ret ~= 0 then 
	print("Mount USB Disk error."); 
	return -1
end

-- copy yahei font file to /root/recovery
os.execute("cp "..udisk_dir.."/font.ttf  /root/recovery/")

return 0