#!/usr/bin/lua

local rootdir = "/root"
local udisk_dir = rootdir.."/udisk/"
local mount_dir

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
	print("Mount USB Disk error, now turn to check local disk.")

	-- mount the second partition to local_dir
	local ldisk_dir = rootdir.."/ldisk/"
	os.execute("mkdir  -p "..ldisk_dir)
--	ret = os.execute("mount -o ro /dev/hda2 "..ldisk_dir)
	ret = os.execute("mount /dev/hda2 "..ldisk_dir)
	if ret ~= 0 then
		print("Mount local disk error!")
		return -1
	end
	-- use files on local disk
	mount_dir = ldisk_dir
else
	-- use files on u disk
	mount_dir = udisk_dir
end

-- copy font file to /root/recovery
os.execute("cp "..mount_dir.."/font.ttf  /root/recovery/")

return 0
