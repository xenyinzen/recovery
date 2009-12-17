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
local rootdir = "/root"
local udisk_dir = rootdir.."/udisk/"
local backup = "/backup/"
local MPNUM = 4
local ret = 0


local sfdisk_prefix = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
]]

-- USB ports on yeeloong
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
			printMsg("找不到匹配的PCI设备号！")
			return -1
		end
        else
		print("Can't find USB disk.")
		printMsg("找不到U盘！")
                return -1
        end
        
        return 0
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
--[[	
	-- for yeeloong only
	local content = GetCMDOutput( "udevinfo --export-db" )
	if content ~= nil and content ~= "" then
		dev, part = FindUSBDisk(content)
	end
--]]	
	-- here, notice different filesystem type: ext2, or fat
	-- for yeeloong, fuloong, and linglong

	part = "/dev/sda1"
	local ret = os.execute( "mount "..part.." "..udisk_dir )
	if ret ~= 0 then
		part = "/dev/sda"
		ret = os.execute( "mount "..part.." "..udisk_dir )
		if ret ~= 0 then 
			part = "/dev/sdb1"			
			ret = os.execute( "mount "..part.." "..udisk_dir )
			if ret ~= 0 then
				part = "/dev/sdb"
				ret = os.execute( "mount "..part.." "..udisk_dir )
				if ret ~= 0 then
					print("mount udisk failed."); 
					printMsg("挂载U盘失败！");
					return -1 
				end			
			end	
		end
		
	end

	return 0
end

function check_md5sum(dir)
	-- calculate actual md5sum value, now files are all in usb disk
	for k, v in pairs( md5sum_t ) do
		local file = dir..k
		local content = GetCMDOutput( "md5sum "..file )
		if content then
			local value, f = content:match(md5sum_pattern)
			if value then
				if value ~= v then
					print("Md5sum check error: "..f)
					return -1
				end
			else
				print("Nil md5sum value: "..file)
				return -1
			end
		else
			print("No this file? : "..file)
			return -1
		end		
	end
	
	return 0
end

function Recover()
	local par = Cfg.default_partitions
	local sfarg = Cfg.sfdisk_arg
	local faction = Cfg.format_table
	local files = Cfg.files_table
	
	if not sfarg or not faction or not files then
		print("Error! Nil parameters are passed in Recover.")
		printMsg("传递给还原程序的参数错误，可能是配置文件格式不正确。")
		return -1
	end
	
	-- do geometry and format action
	print("\n================ Make New Geometry =================")
	printMsg("开始分区……")
	ret = do_cmd { sfdisk_prefix..sfarg }
	if not ret then
		print("Error! Hard disk can not be divided.")
		printMsg("出错，磁盘无法分区！")
		return -1
	end
	printMsg("分区完成。")
	
	print("\n==================== Do Format =====================")
	printMsg("开始格式化……")
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
			printMsg("格式化时出错！")
			return -1
		end
		io.write("OK.\n")
	end
	printMsg("格式化完成。")
	
	-- mount essential partitions to localdir
	-- mount root fs
	local main_i = ""
	for i, v in ipairs(par) do
		if v[MPNUM] == '/' then
			main_i = i
			-- mount root partition
			ret = do_cmd { "mount "..localdisk..i.." "..localdir }
			if not ret then print("mount root fs failed."); printMsg("加载根文件系统失败！"); return -1 end
		end
	end
	
	-- create some directories, and mount other partitions
	for i, v in ipairs(par) do
		if v[MPNUM] then
			local subdir = v[MPNUM]
			if subdir ~= '/' then
				local dir = localdir..subdir
				lfs.mkdir(dir)
				-- mount other partitions
				ret = do_cmd { "mount "..localdisk..i.." "..dir }
				if not ret then print("mount other partitions failed."); printMsg("挂载其它分区失败！"); return -1 end
			end
		
		end	
	end	
	-- create backup directory
	local tmp_dir = localdir..backup
	ret = lfs.mkdir(tmp_dir)
	if not ret then print("make tmp dir failed."); printMsg("创建备份目录失败！"); return -1 end
	if par['Backup'] then
		local backupdev = localdisk..par['Backup']
		ret = do_cmd { "mount "..backupdev.." "..tmp_dir }
		if not ret then 
			print("mount backup device failed. oh...");
		end
	end
	-- mount tmpfs
	do_cmd { "mount none -t tmpfs /tmp" }
	
	-- copy essential files from U disk to local disk
	print("\n=================== Copy Files =====================")
	printMsg("拷贝系统文件到磁盘……")
	-- copy
	for i, v in pairs(files) do
		local cmd = "\ncp -f "..udisk_dir..v[1].." "..tmp_dir
		print(cmd)
	
		if Cfg.verbose then
			ret = do_cmd { cmd }
		else
			lfs.chdir( udisk_dir )
			ret = do_cmd { "bar -c 'cat > "..tmp_dir.."${bar_file}' "..v[1] }
			lfs.chdir( "-" )
		end
	end
	if not ret then print("Copying data file error!"); printMsg("拷贝系统文件时出错！"); return -1 end
	
	local osfab = Cfg.OSFAB_NAME or "OSFab.img"
	print("Copy osfab file.")
	printMsg("拷贝组件映像文件到磁盘……")
	lfs.chdir( udisk_dir )
	ret = do_cmd { "bar -c 'cat > "..tmp_dir.."${bar_file}' "..osfab }
	if not ret then
		print("copy osfab failed.")
		printMsg("拷贝组件映像文件失败！")
		return -1
	end
	-- copy vmlinux, config.txt, boot.cfg and other files to disk
	do_cmd { "cp -a vmlinux "..tmp_dir }
	do_cmd { "cp -a vmlinuz "..tmp_dir }
	do_cmd { "cp -a config.txt "..tmp_dir }
	do_cmd { "cp -a boot.cfg "..tmp_dir }
	do_cmd { "cp -a md5sum.txt "..tmp_dir }
	do_cmd { "sync" }
	lfs.chdir( "/" )
	printMsg("组件映像文件拷贝完成。")
	
	-- Umount the usb disk.
	ret = do_cmd { "umount "..udisk_dir }
	if not ret then
		print("Umount USB disk failed.")
	else
		print("**You can take off the USB disk**")
		printMsg("**现在可以拨出U盘了**")
	end

	-- change directory
	ret = lfs.chdir(tmp_dir)
	if not ret then print("change directory to tmp_dir failed."); printMsg("切换到备份目录失败！"); return -1 end
	
	-- calculate actual md5sum value, now files are all in local disk
	if Cfg.check2 then
		io.write("\n--> Now check the md5sum of files on local disk... "); io.flush()
		printMsg("检查本地磁盘上的文件……")
		ret = check_md5sum('./')
		if ret ~= 0 then 
			io.write("Error when check md5sum of files. \n")
			printMsg("文件md5sum值校验出错。")
			return -1
		else
			io.write("OK.\n")	
			printMsg("文件检查完成。")
		end
	end
	
	-- extract
	print("\n=================== Extract Files ==================")
	printMsg("解压系统文件……")
	for i, v in pairs( files ) do
		local dir = v[2]
		print("\n--> tar xzf "..v[1].." -C "..dir)
		if Cfg.verbose then
			ret = do_cmd { "tar xzvf "..v[1].." -C "..dir }
		else
			ret = do_cmd { "bar "..v[1].." | tar xzf - -C "..dir }		
		end
		if not ret then print("tar error."); printMsg("解压出错！"); return -1 end
	end	

	do_cmd { "sync" }
	printMsg("系统文件解压完成。")
	print("")
	
	-- mount proc fs
	do_cmd { "mount none -t proc "..localdir.."/proc" }
	
	-- generate fstab
	print("Next we generate fstab file.")
	local fd = io.open(localdir.."/etc/fstab", "w")
	fd:write("#<file system>\t<mount point>\t<type>\t<options>\t<dump>\t<pass>\n")

	for i, v in ipairs(par) do
		-- for normal partitions
		if v[MPNUM] then
			if v[MPNUM] ~= '/' then
				fd:write("/dev/hda"..i..'\t')
				fd:write(v[MPNUM]..'\t')
				fd:write(v[2]..'\t')
				fd:write("defaults\t")
				fd:write("0\t0\n")
			end
		end	
		-- for swap partition 
		if v[2] == "swap" then
			fd:write("/dev/hda"..i..'\t')
			fd:write("none\t")
			fd:write("swap\t")
			fd:write("sw\t")
			fd:write("0\t0\n")
		end
	end
	-- add tmpfs
	fd:write("shm\t")
	fd:write("/tmp\t")
	fd:write("tmpfs\t")
	fd:write("defaults\t")
	fd:write("0\t0\n")
	fd:close()

	local bc = Cfg.default_bootcfg
	if bc then
		-- generate boot.cfg on /boot
		print("Next we generate boot.cfg file.")
		local bootn = par['Boot'] or 1
		local bootdir = "/bootcfg/"
		lfs.mkdir(bootdir)
		ret = do_cmd { "mount "..localdisk..bootn.." "..bootdir }
		if not ret then 
			print("Mount boot partition failed.")
			return -1	
		end
		local fd = io.open(bootdir.."boot.cfg", "w")
		fd:write("default "..(bc.default_boot or 0)..'\n')
		fd:write("showmenu "..(bc.show_menu or 1)..'\n\n')
		fd:write("title "..(bc.title or "Lemote System")..'\n')
		local ch = string.char(string.byte('a') + main_i - 1)
		fd:write("\tkernel /dev/fs/ext2@wd0"..ch.."/boot/vmlinux\n")
		fd:write("\targs console=tty no_auto_cmd quiet root=/dev/hda"..(main_i or 1).." machtype="..(bc.machtype or "yeeloong").." "..(bc.res or ""))
		fd:close()
	end
		
	do_cmd { "sync" }	
--	lfs.chdir("/")
	print(  "======================= Main Body End ========================")
	
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
	for _, v in ipairs(Cfg.format_types) do
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
			print("Error! One of the size in column Size is not number, NULL, or rest.")
			printMsg("Size参数不正确！")
			return -1
		end
		
		-- column two
		if not r_format_types[format_type] then
			print("Error! One of the type of format in column Type is not right. \nOnly ext2, ext3, swap, extend is permitted.")	
			printMsg("Format type参数不正确！")
			return -1
		end 
		
		-- column three
		if format ~= 'Y' and format ~= 'N' and format ~= 'NULL' then
			print("Error! One of the value in column Format is not right. \nOnly Y, N, NULL are permitted.")
			printMsg("是否格式化标志不正确！")
			return -1
		end
		
		-- the rest columns must all be string
		-- so don't need to check them  
	
	end
	-----------------------------------------------------------------------
	-- The following codes don't need to judge the print
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
			Cfg.format_table[i] = {}
			Cfg.format_table[i][1] = "mkswap "..localdisk..i
			Cfg.format_table[i][2] = true
		
		elseif format_type == 'fat' then
			Cfg.format_table[i] = {}
			Cfg.format_table[i][1] = "mkfs.vfat "..localdisk..i		
			if format == 'Y' then
				Cfg.format_table[i][2] = true
			else
				Cfg.format_table[i][2] = false
			end
		elseif format_type == 'ext3' then
		 	Cfg.format_table[i] = {}
			Cfg.format_table[i][1] = "mkfs.ext3 "..localdisk..i
			if format == 'Y' then
				Cfg.format_table[i][2] = true
			else
				Cfg.format_table[i][2] = false
			end
		elseif format_type == 'ext2' then
			Cfg.format_table[i] = {}
			Cfg.format_table[i][1] = "mkfs.ext2 "..localdisk..i
			if format == 'Y' then
				Cfg.format_table[i][2] = true
			else
				Cfg.format_table[i][2] = false
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
				Cfg.files_table[file_count][2] = localdir..v[MPNUM]..'/'
			end		
		end
				
	end
	
--[[	-- next we will choose machine type boot cfg
	local fd = io.open(udisk_dir.."boot.cfg", "r")
	if fd then
		content = fd:read("*a")
		if content then
			-- clear comment lines
			content = content:gsub("%#.-\n", "")
			-- collect info
			--title = content:match("title (.-)\n")
			title = Cfg.SYSTEM_NAME or "Cocreate Linux Desktop for Loongson"
			machtype = content:match("machtype=([%w_%-]+)")
			res = content:match("video=[%a%:]*%d+[xX]%d+%-%d%d%@%d%d")
			Cfg.default_bootcfg = {}
			Cfg.default_bootcfg.title = title
			Cfg.default_bootcfg.machtype = machtype
			Cfg.default_bootcfg.res = res
		end
		fd:close()
	else
		print("Missing boot.cfg file on usb disk?")
		printMsg("缺少机器类型配置: boot.cfg?")
	
		return -1
	end
--]]

	-- next we will choose machine type boot cfg
	local fd = io.open("/proc/cmdline", "r")
	if fd then
		content = fd:read("*a")
		if content then
			-- clear comment lines
			-- content = content:gsub("%#.-\n", "")
			-- collect info
			--title = content:match("title (.-)\n")
			title = Cfg.SYSTEM_NAME or "Cocreate Linux Desktop for Loongson"
			machtype = content:match("machtype=([%w_%-]+)")
			res = content:match("video=[%a%:]*%d+[xX]%d+%-%d%d%@%d%d")
			Cfg.default_bootcfg = {}
			Cfg.default_bootcfg.title = title
			Cfg.default_bootcfg.machtype = machtype
			Cfg.default_bootcfg.res = res
		end
		fd:close()
	else
		print("Missing /proc/cmdline file in system?")
		printMsg("缺少机器类型配置: /proc/cmdline?")
	
		return -1
	end

	
	return 0
end

--===================================================================
-- START
--===================================================================
-- mt.sleep(10)
do_cmd { "date -s 21990909" }
do_cmd { "setterm -blank 0" }

-- lfs.mkdir(udisk_dir)
--
-- find U disk, mount it, and copy essential files into inner disk
--
-- ret = FindAndMountUDisk()
-- if not ret then print("Mount USB Disk error.") end


PrintHead()

-- find the size of local disk
local fdisk_output = GetCMDOutput( "fdisk -l" )
local real_disksize, unit = fdisk_output:match(": ([%d%.]+) ([GM])B,")
real_disksize = tonumber(real_disksize)
-- convert megabytes to gigabytes
if unit == 'M' then
	real_disksize = real_disksize / 1024;
end

-- self containing
if not printMsg then
	printMsg = print
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
		print("The disksize specified in config.txt is too big.")
		printMsg("配置文件中指定的磁盘大小过大（大于实际磁盘容量）！请修改此参数。")
		return -1
	end
else
	print("Can't find external configuration file: config.txt.")
	printMsg("无法找到外部配置文件！请检查。")
	return -1
end

--
-- before recovery, we want a memory test
--
if Cfg.premem then
	print("\n--> Pre Memory Test")
	ret = do_cmd { "memtester_little 960 1" }
	if not ret then print("Memory test is failed. Error!"); return -1 end
end

if Cfg.check1 then
	-- read md5sum.txt
	local fd = io.open(udisk_dir.."md5sum.txt", 'r')
	if not fd then 
		print("Can't find file: md5sum.txt. We will not execute md5sum check."); 
		printMsg("找不到md5sum.txt文件，将不会进行md5sum值校验。") 
		Cfg.check1 = false
		Cfg.check2 = false
	end
	
	if Cfg.check1 then
		local md5_file = fd:read("*a")
		fd:close()
		-- retrieve md5sum value of every bin file, files in md5sum can be more than actual file number
		local l = 1
		local value, filename
		while l do
			_, l, value, filename = md5_file:find(md5sum_pattern, l)
			if l then 
				md5sum_t[filename] = value
			end
		end

		-- calculate actual md5sum value, now files are all in usb disk
		io.write("--> Now check the md5sum of files on usb disk... "); io.flush()
		printMsg("检查U盘上的文件的完整性")
		ret = check_md5sum(udisk_dir)
		if ret ~= 0 then 
			io.write("Error when check md5sum of files. \n")
			printMsg("文件md5sum值校验出错。")
			return -1
		else
			io.write("OK.\n")	
			printMsg("文件检查完成。")
		end
	end
end


local ret = Recover()
if ret ~= 0 then print("Error when recover.") return -1 end

print("Next we will install some components, please wait by patience...")
printMsg("下面安装组件，可能需要几分钟，请耐心等待。")
-- action for OSFab image
local osfab = Cfg.OSFAB_NAME
local machine = Cfg.default_bootcfg.machtype
local version = Cfg.SYSTEM_VERSION
local resolution = Cfg.default_bootcfg.res
local backup_dir = localdir..backup
local fabdir = "/osfab"

print("make /osfab directory.")
do_cmd { "mkdir -p "..fabdir } 

print("Mount osfab file.")
ret = do_cmd { "mount "..backup_dir..osfab.." -t ext2 -o ro,loop "..fabdir } 
if not ret then
	print("Mount osfab file failed.")
	printMsg("挂载组件映像文件失败！")
	return -1
end

if not putENV then
	print("Have no putENV function. Stop.")
	return -1
end

local s = (resolution or "1024x768"):match("%d+[xX]%d+")
-- set three environment variables
putENV("MOUNT_POINT="..(localdir or "/mnt"))
putENV("MACHINE_TYPE="..(machine or "yeeloong"))
putENV("SYSTEM_VERSION="..(version or ""))
putENV("RESOLUTION="..(s or "1024x768"))

lfs.chdir(fabdir)

print("Install osfab files...")
printMsg("正在安装组件……")
ret = do_cmd { "bash select_install.sh 1>>"..backup_dir.."log.txt 2>&1" }
if not ret then 
	print("Install components failed.");
	printMsg("安装组件时出错！")
	return -1
end
printMsg("组件安装完成。")

do_cmd { "echo '============================= END ============================' >> "..backup_dir.."log.txt" }

PrintBigPass()
return 0
-- do_cmd { "reboot" }
--==================================================================
-- END
--==================================================================

