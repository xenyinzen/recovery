#!/usr/bin/lua

package.path = package.path.."?.lua;../?.lua;../lib/?.lua;../../../lib/?.lua;"
package.cpath = package.cpath.."?.so;../?.so;../lib/?.so;../../../lib/?.so;"

require "mt_lib"
require "localcfg"

local md5sum_t = {}
local md5sum_pattern = "(%w+)  ([%w%./%-_]+)[ \t\r]*\n"
local udisk_dir = "/mnt/udisk/"
local external_config = 'config.txt'
local localdisk = "/dev/hda"
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
				ret = do_cmd { v }
			end
		else
			ret = do_cmd { v..HO }
		end
		if not ret then
			print("Error! Some error occured when format.")
			return -1
		end
		io.write("OK.\n")
	end
	
	-- copy essential files from U disk to local disk
	print("\n=================== Copy Files =====================")
	local dst_dir = {}
	for i, v in pairs(files) do
		dst_dir[i] = "/mnt/hda"..v[2]
		-- equal to mkdir -p, so if directory already exists, this statement have no effect
		lfs.mkdir(dst_dir[i])
		-- judge whether mounted already
		local content = GetCMDOutput( "mount" )
		if not content:find(dst_dir[i]) then
			ret = do_cmd { "mount /dev/hda"..v[2].." "..dst_dir[i] }
			if not ret then return -1 end
		end
	end

	local tmp_par = Cfg.default_partitions['tmp_partition']
	local tmp_m = "/mnt/hda"..tmp_par
	local tmp_dir = "/mnt/hda"..tmp_par..'/'..Cfg.default_partitions['tmp_dir']
	-- judge whether mounted already
	local content = GetCMDOutput( "mount" )
	if not content:find(tmp_m) then
		lfs.mkdir(tmp_m)
		ret = do_cmd { "mount /dev/hda"..tmp_par.." "..tmp_m }
		if not ret then return -1 end
	end
	ret = lfs.mkdir(tmp_dir)
	if not ret then return -1 end
	
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
		print("\n--> tar xzf "..v[1].." -C "..dst_dir[i])
		if Cfg.verbose then
			ret = do_cmd { "tar xzvf "..v[1].." -C "..dst_dir[i] }
		else
			ret = do_cmd { "bar "..v[1].." | tar xzf - -C "..dst_dir[i] }		
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

	local defpar = Cfg.default_partitions
	local args = ""
	local n = table.maxn(defpar)
	
	local r_format_types = {}
	for _, v in ipairs(format_types) do
		r_format_types[v] = true		
	end
	
	-- arguments check
	for i = 1, (n/4-1) do
		local index = defpar[1 + i*4]
		local size = defpar[2 + i*4]
		local format_type = defpar[3 + i*4]
		local format = defpar[4 + i*4]
		
		if type(index) ~= 'number' then
			exception("Error! One of the index in column Num is not number.")
		end
		
		if type(size) ~= 'number' 
		and size ~= 'NULL' 
		and size ~= 'rest' 
		then
			exception("Error! One of the size in column Size is not number, NULL, or rest.")
		end
		
		if not r_format_types[format_type] then
			exception("Error! One of the type of format in column Type is not right. \nOnly ext2, ext3, swap, extend is permitted.")	
		end 
		
		if format ~= 'Y' and format ~= 'N' and format ~= 'NULL' then
			exception("Error! One of the value in column Format is not right. \nOnly Y, N, NULL are permitted.")
		end
	
	end
	-----------------------------------------------------------------------
	-- The following codes don't need to judge the exception
	-----------------------------------------------------------------------
	-- 
	for i = 1, (n/4-1) do
		local index = defpar[1 + i*4]
		local size = defpar[2 + i*4]
		local format_type = defpar[3 + i*4]
		local format = defpar[4 + i*4]
	
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
	for i = 1, (n/4-1) do
		local index = defpar[1 + i*4]
		local size = defpar[2 + i*4]
		local format_type = defpar[3 + i*4]
		local format = defpar[4 + i*4]
	
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
	n = table.maxn(Cfg.files)
	for i = 1, (n/3-1) do
		local name = Cfg.files[1+i*3]
		local par = Cfg.files[2+i*3]
		local extract = Cfg.files[3+i*3]
		
		if extract == 'Y' then
			Cfg.files_table[i] = {}
			Cfg.files_table[i][1] = name
			Cfg.files_table[i][2] = par
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
	dofile(extern_cfg_file)
	-- if external disksize is smaller than internal disksize, go ahead normally
	if Cfg.disksize <= real_disksize then
		-- after this function, the config table has been transformed as the internal expresstion
		collect_info()		
	else
		exception("The disksize specified in config.txt is too big.")
	
	end
else
	exception("Can't find external configuration file: config.txt .")
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
if not fd then exception("Can't find file: md5sum.txt .") end
local md5_file = fd:read("*a")
fd:close()

-- retrieve md5sum value of every tar.gz file
local l = 1
local i = 0
local value, filename
while l do
	_, l, value, filename = md5_file:find(md5sum_pattern, l)
	if l then md5sum_t[filename] = value; i = i + 1 end
end
if i ~= #(Cfg.files)/3-1 then
	exception("md5sum.txt have different number of file items.")
end

if Cfg.check1 then
	-- calculate actual md5sum value, now files are all in usb disk
	io.write("--> Now check the integrity of files in usb disk... "); io.flush()
	local files = Cfg.files
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
			exception("Get md5sum output error: "..file)
		end		
	end
	io.write("OK.\n")	
end


local ret = Recover()
if ret ~= 0 then exception() end

PrintBigPass()
do_cmd { "reboot" }
--==================================================================
-- END
--==================================================================

