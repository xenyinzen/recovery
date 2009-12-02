#!/usr/bin/lua

package.path = package.path.."?.lua;../?.lua;../lib/?.lua;../../../lib/?.lua;"
package.cpath = package.cpath.."?.so;../?.so;../lib/?.so;../../../lib/?.so;"

require "mt_lib"
require "localcfg"

local md5sum_t = {}
local md5sum_pattern = "(%w+)  ([%w%./%-_]+)[ \t\r]*\n"
local external_config = 'config.txt'
local localdisk = "/dev/hda"
local localdir = "/mnt/"
local udisk_dir = localdir.."/udisk/"
local MPNUM = 4
local ret


local sfdisk_prefix = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
]]


function exception( str )
 	if str then print(str) end
 	PrintBigFailure()
 	print("Failed. Press 'Enter' to exit.")
	io.read()
	print("Now exit!")
--	do_cmd { "poweroff" }; mt.sleep(10000);
	os.exit(-1)
end

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
			return -1
		end
        else
		print("Can't find USB disk.")
                return -1
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
	if not ret then return -1 end

	return 0
end

function Recover()
	local par = Cfg.default_partitions
	local sfarg = Cfg.sfdisk_arg
	local faction = Cfg.format_table
	local files = Cfg.files_table
	
	if not sfarg or not faction or not files then
		exception("Error! Nil parameters are passed in Recover.")
	end
	
	-- do geometry and format action
	print("\n================ Make New Geometry =================")
	ret = do_cmd { sfdisk_prefix..sfarg }
	if not ret then
		print("Error! Hard disk can not be divided.")
		return -1
	end
	
	print("\n==================== Do Format =====================")
	for i, v in pairs(faction) do
		io.write('--> '..v[1].." ... "); io.flush()
		if Cfg.verbose then
			-- if permit format
			if v[2] then
				ret = do_cmd { v[1] }
			end
		else
			ret = do_cmd { v[1]..HO }
		end
		if not ret then
			print("Error! Some error occured when format.")
			return -1
		end
		io.write("OK.\n")
	end
	
	-- mount essential partitions to localdir
	-- mount root fs
	local main_file = ""
	for i, v in ipairs(Cfg.partitions) do
		if v[MPNUM] == '/' then
			main_file = v[MPNUM+1]
			-- mount root partition
			ret = do_cmd { "mount "..localdisk..i.." "..localdir }
			if not ret then return -1 end
		end
	end
	
	-- create some directories, and mount other partitions
	for i, v in ipairs(Cfg.partitions) do
		if v[MPNUM] then
			local subdir = v[MPNUM]
			if subdir ~= '/' then
				local dir = localdir..subdir
				lfs.mkdir(dir)
				-- mount other partitions
				ret = do_cmd { "mount "..localdisk..i.." "..dir }
				if not ret then return -1 end
			end
		
		end	
	end	
	-- create backup directory
	local tmp_dir = localdisk..par['tmp_dir']
	ret = lfs.mkdir(tmp_dir)
	if not ret then return -1 end
	
	
	-- copy essential files from U disk to local disk
	print("\n=================== Copy Files =====================")

	-- copy
	for i, v in pairs(files) do
		local cmd = "\ncp -f "..udisk_dir.." "..v[1].." "..tmp_dir
		print(cmd)
	
		if Cfg.verbose then
			ret = do_cmd { cmd }
		else
			lfs.chdir( udisk_dir )
			ret = do_cmd { "bar -c 'cat > "..tmp_dir.."${bar_file}' "..v[1] }
			lfs.chdir( "-" )
		end
	end
	if not ret then exception("Copying tar.gz file error!") end

	ret = do_cmd { "cp -af "..udisk_dir.."vmlinux "..tmp_dir }
	if not ret then exception("Copying vmlinux file error!") end
		
	-- change directory
	lfs.chdir(tmp_dir)
	
	-- calculate actual md5sum value, now files are all in local disk
	io.write("\n--> Now check the integrity of files in local disk... "); io.flush()
	for i, v in pairs( files ) do
		local content = GetCMDOutput( "md5sum "..v[1] )
		if content then
			local value, f = content:match(md5sum_pattern)
			if value then
				if value ~= md5sum_t[v[1]] then
					exception("Md5sum check error: "..f)
				end
			else
				exception("Nil md5sum value: "..v[1])
			end
		else
			exception("Get md5sum output error: "..v[1])
		end	
	end
	io.write("OK.\n")	

	-- extract
	print("\n=================== Extract Files ==================")
	for i, v in pairs( files ) do
		local dir = localdir..v[2]
		print("\n--> tar xzf "..v[1].." -C "..dir)
		if Cfg.verbose then
			ret = do_cmd { "tar xzvf "..v[1].." -C "..dir }
		else
			ret = do_cmd { "bar "..v[1].." | tar xzf - -C "..dir }		
		end
		if not ret then return -1 end
	end	

	do_cmd { "sync" }
	print(  "======================= End ========================")
	print("")
		
	lfs.chdir("/")
	
	-- clean
	if Cfg.clean then
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

function collect_info()

	local par = Cfg.default_partitions
	local args = ""
	
	local r_format_types = {}
	for _, v in ipairs(format_types) do
		r_format_types[v] = true		
	end
	
	-- arguments check
	for i = 1, #par do
		local size = par[i][1]
		local format_type = par[i][2]
		local format = par[i][3]
		
		-- column one
		if type(size) ~= 'number' 
		and size ~= 'NULL' 
		and size ~= 'rest' 
		then
			exception("Error! One of the size in column Size is not number, NULL, or rest.")
		end
		
		-- column two
		if not r_format_types[format_type] then
			exception("Error! One of the type of format in column Type is not right. \nOnly ext2, ext3, swap, extend is permitted.")	
		end 
		
		-- column three
		if format ~= 'Y' and format ~= 'N' and format ~= 'NULL' then
			exception("Error! One of the value in column Format is not right. \nOnly Y, N, NULL are permitted.")
		end
		
		-- the rest columns must all be string
		-- so don't need to check them  
	
	end
	-----------------------------------------------------------------------
	-- The following codes don't need to judge the exception
	-----------------------------------------------------------------------
	-- 
	for i = 1, #par do
		local size = par[i][1]
		local format_type = par[i][2]
		local format = par[i][3]
	
		-- form sfdisk_arg
		if type(size) == 'number' then
			if format_type == "swap" then
				args = args..','..tostring(size)..",S\n"
			else	
				args = args..','..tostring(size)..",L\n"
			end
		elseif size == 'NULL' then
			args = args..",,E\n"
		elseif size == 'rest' then
			args = args..",,\n"
		end
	end
	args = args.."EOF\n"			

	-- till now, sfdisk_arg has been formed
	Cfg.sfdisk_arg = args
	
	-- next, we are going to form format_table: have two columns, only record real parititions 
	for i = 1, #par do
		local size = par[i][1]
		local format_type = par[i][2]
		local format = par[i][3]
	
		-- form format_table
		if format_type == 'extend' then
			-- nothing to do
			
		elseif format_type == 'swap' then
			Cfg.format_table[index] = {}
			Cfg.format_table[index][1] = "mkswap "..localdisk..index
			Cfg.format_table[index][2] = true
		
		elseif format_type == 'fat' then
			Cfg.format_table[index] = {}
			Cfg.format_table[index][1] = "mkfs.vfat "..localdisk..index		
			if format == 'Y' then
				Cfg.format_table[index][2] = true
			else
				Cfg.format_table[index][2] = false
			end
		elseif format_type == 'ext3' then
			Cfg.format_table[index] = {}
			Cfg.format_table[index][1] = "mkfs.ext3 "..localdisk..index
			if format == 'Y' then
				Cfg.format_table[index][2] = true
			else
				Cfg.format_table[index][2] = false
			end
		elseif format_type == 'ext2' then
			Cfg.format_table[index] = {}
			Cfg.format_table[index][1] = "mkfs.ext2 "..localdisk..index
			if format == 'Y' then
				Cfg.format_table[index][2] = true
			else
				Cfg.format_table[index][2] = false
			end
		end
	end
	
	-- next we will form files_table: have two columns, and only record files will be extracted
	local file_count = 0
	for i = 1, #par do
		local v = par[i]
		local n = #v
		-- collect files
		if n > MPNUM then
			for j = MPNUM+1, n do
				file_count = file_count + 1
				Cfg.files_table[file_count] = {}
				Cfg.files_table[file_count][1] = v[j]
				Cfg.files_table[file_count][2] = localdir..v[MPNUM]
			end		
		end
				
	end

end

--===================================================================
-- START
--===================================================================
mt.sleep(10)
do_cmd { "date -s 21990909" }
do_cmd { "setterm -blank 0" }
lfs.mkdir(udisk_dir)

--
-- find U disk, mount it, and copy essential files into inner disk
--
ret = FindAndMountUDisk()
if not ret then exception("Mount USB Disk error.") end


PrintHead()

-- find the size of local disk
local fdisk_output = GetCMDOutput( "fdisk -l" )
local real_disksize, unit = fdisk_output:match(": ([%d%.]+) ([GM])B,")
real_disksize = tonumber(real_disksize)
-- convert megabytes to gigabytes
if unit == 'M' then
	real_disksize = real_disksize / 1024;
end


-- load external config file
local extern_cfg_file = udisk_dir..external_config
if lfs.attributes(extern_cfg_file) then
	-- here, if config.txt has error in it, dofile will report error and exit immediately
	dofile(extern_cfg_file)
	
	-- if external disksize is smaller than internal disksize, go ahead normally
	if Cfg.disksize <= real_disksize then
		-- after this function, the config table has been transformed as the internal expresstion
		-- Cfg.default_partitions
		-- Cfg.sfdisk_arg
		-- Cfg.format_table
		-- Cfg.files_table
		collect_info()		
	else
		exception("The disksize specified in config.txt is too big.")
	end
else
	exception("Can't find external configuration file: config.txt.")
end

--
-- before recovery, we want a memory test
--
if Cfg.premem then
	print("\n--> Pre Memory Test")
	ret = do_cmd { "memtester_little 960 1" }
	if not ret then exception("Memory test is failed. Error!") end
end

-- read md5sum.txt
local fd = io.open(udisk_dir.."md5sum.txt", 'r')
if not fd then exception("Can't find file: md5sum.txt.") end
local md5_file = fd:read("*a")
fd:close()

-- retrieve md5sum value of every tar.gz file, files in md5sum can be more than actual file number
local l = 1
local value, filename
while l do
	_, l, value, filename = md5_file:find(md5sum_pattern, l)
	if l then 
		md5sum_t[filename] = value
	end
end

if Cfg.check1 then
	-- calculate actual md5sum value, now files are all in usb disk
	io.write("--> Now check the integrity of files in usb disk... "); io.flush()
	local files = Cfg.files_table
	for i, v in ipairs( files ) do
		local file = udisk_dir..v
		local content = GetCMDOutput( "md5sum "..file )
		if content then
			local value, f = content:match(md5sum_pattern)
			if value then
				if value ~= md5sum_t[v] then
					exception("Md5sum check error: "..f)
				end
			else
				exception("Nil md5sum value: "..file)
			end
		else
			exception("No this file? : "..file)
		end		
	end
	io.write("OK.\n")	
end


local ret = Recover()
if ret ~= 0 then exception() end

PrintBigPass()
-- do_cmd { "reboot" }
--==================================================================
-- END
--==================================================================
