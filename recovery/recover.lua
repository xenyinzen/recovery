#!/usr/bin/lua

package.path = package.path.."?.lua;../?.lua;../lib/?.lua;../../../lib/?.lua;"
package.cpath = package.cpath.."?.so;../?.so;../lib/?.so;../../../lib/?.so;"

require "mt_lib"
require "localcfg"

local verbose = cfg.verbose

local md5sum_t = {}
local udisk_dir = "/mnt/udisk/"


function FindUSBDisk( content )
	local u_disks = {
	        [1] = "ID_PATH=pci-0000:00:0e.5-usb-0:2:1.0-scsi-0:0:0:0",
	        [2] = "ID_PATH=pci-0000:00:0e.5-usb-0:3:1.0-scsi-0:0:0:0",
	        [3] = "ID_PATH=pci-0000:00:09.1-usb-0:2:1.0-scsi-0:0:0:0",
	        [4] = "ID_PATH=pci-0000:00:09.0-usb-0:2:1.0-scsi-0:0:0:0",
        }
        local l = 1
        local block_start, l, dev, part = content:find("block@(sd%a)@(sd%a%d)\n", l)
        if block_start > 0 then block_start = block_start - 3 end
        
        local block_end = content:find("\n\n", l)
        if block_end > 0 then block_end = block_end - 1 end
        
        local subblock = content:sub(block_start, block_end)
        
        if #subblock > 0 then 
                str = subblock:match("(ID_PATH=%S+)\n")
        	if str then
			for i, v in ipairs(u_disks) do
				if str:upper() == v:upper() then
				      return '/dev/'..dev, '/dev/'..part, i                         
				end
			end
			
			print("Can't find matched pci serials number.")
			return 1
		end
        else
		print("Can't find USB disk.")
                return 1
        end
end

function GetCMDOutput( cmd )
	local fp = io.popen( cmd, "r" )
	local content = fp:read("*a")
	fp:close()
	
	if content == "" then content = nil end
	
	return content	
end

function FindAndMountUDisk()
	local dev, part
	
	
	local content = GetCMDOutput( "udevinfo --export-db" )
	if content ~= nil and content ~= "" then
		dev, part = FindUSBDisk(content)
	end
	
	-- here, notice different filesystem type: ext2, or fat
	local ret = do_cmd { "mount "..part.." "..udisk_dir }
	if not ret then return 1 end

	return 0
end

function Recover( disk_size )
	local geometry_action
	local format_action
	local scheme
	local ret
	
	-- choose a format disk scheme
	if cfg.scheme_choice then
		scheme = cfg.scheme_choice
	elseif disk_size == 2.0 then
		scheme = cfg.scheme_2G
	elseif disk_size == 160.0 then
		scheme = cfg.scheme_120_160G
	end
	
	geometry_action = scheme.geometry_action
	format_action = scheme.format_action
	
	if cfg.newgeometry then
	-- do geometry and format action
	print("\n================ Make New Geometry =================")
	ret = do_cmd { geometry_action }
	if not ret then
		print("Error! Hard disk can not be made new geometry on.")
		return 1
	end
	end
	
	if cfg.newformat then
	print("\n==================== Do Format =====================")
	for i, v in ipairs(format_action) do
		print('--> '..v)
		if verbose then
			ret = do_cmd { v }
		else
			ret = do_cmd { v..HO }
		end
		if not ret then
			print("Error when format.")
			return 1
		end
	end
	end
	
	-- copy essential files from U disk to local disk
	print("\n=================== Copy Files =====================")
	
	local dst_dir = {}
	local dstp = scheme.dst_partition
	for i, v in ipairs(dstp) do
		dst_dir[i] = "/mnt/"..v
		lfs.mkdir(dst_dir[i])
		-- judge whether mounted already
		local content = GetCMDOutput( "mount" )
		if not content:find(dst_dir[i]) then
			ret = do_cmd { "mount /dev/"..v.." "..dst_dir[i] }
			if not ret then return 1 end
		end
	end

	local tmp_dir = "/mnt/"..scheme.tmp_dir
	lfs.mkdir(tmp_dir)
	print("\ncp -rf "..udisk_dir.."* "..tmp_dir)
	if verbose then
		ret = do_cmd { "cp -rf "..udisk_dir.."* "..tmp_dir }
	else
		lfs.chdir( udisk_dir )
		ret = do_cmd { "bar -c 'cat > "..tmp_dir.."${bar_file}' *.tar.gz" }
		lfs.chdir( "-" )
	end
	if not ret then return 1 end
	
	-- change directory
	lfs.chdir(tmp_dir)
	
	-- calculate actual md5sum value, now files are all in local disk
	print("\nNow check the integrity of files in local disk...")
	local files = scheme.system_files
	for i, v in ipairs( files ) do
		local content = GetCMDOutput( "md5sum "..v )
		if content then
			local value, f = content:match("(%w+)  ([%w%./]+)\n")
			if value then
				if value ~= md5sum_t[v] then
					exception("Md5sum check error: "..f)
				end
			else
				exception("Nil md5sum value: "..v)
			end
		else
			exception("Get md5sum output error: "..v)
		end		
	end	

	-- extract
	print("\n=================== Extract Files ==================")
	local files = scheme.system_files
	
	for i, v in ipairs( files ) do
		print("\n--> tar xzf "..v.." -C "..dst_dir[i])
		if verbose then
			ret = do_cmd { "tar xzvf "..v.." -C "..dst_dir[i] }
		else
			ret = do_cmd { "bar "..v.." | tar xzf - -C "..dst_dir[i] }		
		end
		if not ret then return 1 end
	end	
	
	do_cmd { "sync" }

	print(  "======================= End ========================")
	print("")
		
	lfs.chdir("/")
	
	-- clean
	if cfg.clean then
		do_cmd { "rm -rf "..tmp_dir.."/*" }
	end
			
	return 0
end

function PrintHead()

	do_cmd { "clear" }
	print("")
	print("=====================================================================")
	print("||                                                                 ||")
	print("||                         START RECOVERY                          ||")
	print("||                                                                 ||")
	print("=====================================================================")
	print("")
	mt.sleep(2)
end

function PrintBigPass()
	local big_pass = [[
			=========================================================
 			|                                                       |
			|        ########      ###      ######    ######        |
			|        ##     ##    ## ##    ##    ##  ##    ##       |
			|        ##     ##   ##   ##   ##        ##             |
			|        ########   ##     ##   ######    ######        |
			|        ##         #########        ##        ##       |
			|        ##         ##     ##  ##    ##  ##    ##       |
			|        ##         ##     ##   ######    ######        |
			|                                                       |
			=========================================================
	]]
	print(big_pass)
	mt.sleep(3)
end


function PrintBigFailure()
	local big_failure = [[
			=========================================================
			|                                                       |
			|  ########    ###    #### ##       ######## ########   |
			|  ##         ## ##    ##  ##       ##       ##     ##  |
			|  ##        ##   ##   ##  ##       ##       ##     ##  |
			|  ######   ##     ##  ##  ##       ######   ##     ##  |
			|  ##       #########  ##  ##       ##       ##     ##  |
			|  ##       ##     ##  ##  ##       ##       ##     ##  |
			|  ##       ##     ## #### ######## ######## ########   |
			|                                                       |
			========================================================= 
	]]
	
	print(big_failure)

end

function exception( str )
 	if str then print(str) end
 	PrintBigFailure()
 	print("Failed. Press 'Enter' to exit.")
	io.read()
	print("Now exit!")
--	do_cmd { "poweroff" }; mt.sleep(10000);
	os.exit(1)
end

--===================================================================
-- START
--===================================================================
mt.sleep(10)
do_cmd { "date -s 20090909" }
do_cmd { "setterm -blank 0" }
lfs.mkdir(udisk_dir)

--
-- find U disk, mount it, and copy essential files into inner disk
--
local ret = FindAndMountUDisk()
if not ret then exception("Mount USB Disk error.") end


PrintHead()

-- load external config file
local extern_cfg_file = udisk_dir.."config.txt"
if lfs.attributes(extern_cfg_file) then
	dofile(extern_cfg_file)
	if cfg.disksize then
		if cfg.disksize <= 8 then
			cfg.scheme_choice = cfg.scheme_2G
		elseif cfg.disksize >= 120 and cfg.disksize <= 160 then
			cfg.scheme_choice = cfg.scheme_120_160G
		end
	end
else
	exception("Can't find external configuration file: config.txt .")
end

-- read md5sum.txt
local fd = io.open(udisk_dir.."md5sum.txt", 'r')
if not fd then exception("Can't find file: md5sum.txt .") end
local md5_file = fd:read("*a")
fd:close()

-- retrieve md5sum value of every tar.gz file
local l = 1
local i = 0
local value, filename
while l do
	_, l, value, filename = md5_file:find("(%w+)  ([%w%.]+)\n", l)
	if l then md5sum_t[filename] = value; i = i + 1 end
end
if i ~= #(cfg.scheme_choice.system_files) then
	exception("md5sum.txt have different number of file items.")
end

if cfg.checkfirst then
	-- calculate actual md5sum value, now files are all in usb disk
	print("Now check the integrity of files in usb disk...")
	local files = cfg.scheme_choice.system_files
	for i, v in ipairs( files ) do
		local file = udisk_dir..v
		local content = GetCMDOutput( "md5sum "..file )
		if content then
			local value, f = content:match("(%w+)  ([%w%./]+)\n")
			if value then
				if value ~= md5sum_t[v] then
					exception("Md5sum check error: "..f)
				end
			else
				exception("Nil md5sum value: "..file)
			end
		else
			exception("Get md5sum output error: "..file)
		end		
	end	
end

if cfg.checksecond then
	-- Check UDisk Files
	print("================ Check UDisk Files ================")
	print("")
	local files = cfg.scheme_choice.system_files

	for i, v in ipairs( files ) do
		v = udisk_dir..v
		print("\n----------- tar tzf "..v.." --------------\n")
		ret = do_cmd { "tar tzf "..v }
		if not ret then exception("Pretar list check error.") end
	end	
end

local fdisk_output = GetCMDOutput( "fdisk -l" )
local disk_size = fdisk_output:match(": (%d+%.%d) GB,")
disk_size = tonumber(disk_size)

local ret = Recover( disk_size )
if ret ~= 0 then exception() end

PrintBigPass()
do_cmd { "reboot" }
--==================================================================
-- END
--==================================================================

