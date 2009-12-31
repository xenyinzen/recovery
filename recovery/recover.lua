#!/usr/bin/lua

package.path = package.path.."?.lua;../?.lua;../lib/?.lua;../../../lib/?.lua;"
package.cpath = package.cpath.."?.so;../?.so;../lib/?.so;../../../lib/?.so;"

require "mt_lib"
-- require "localcfg"

local md5sum_t = {}
local md5sum_pattern = "(%w+)  ([%w%./%-_]+)[ \t\r]*\n"
local external_config = 'config.txt'
local localdisk = "/dev/hda"
local localdir = "/mnt/"
local rootdir = "/root"
local udisk_dir = rootdir.."/udisk/"
local ldisk_dir = rootdir.."/ldisk/"
local mount_dir
local backup = "/backup/"
local home_backup = "home_backup.tar.gz"
local MPNUM = 4
local ret = 0
local root_i = 0
local home_i = 0

local sfdisk_prefix = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
]]

function GetCMDOutput( cmd )
	local fp = io.popen( cmd, "r" )
	local content = fp:read("*a")
	fp:close()
	
	if content == "" then content = nil end
	
	return content	
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
	
	-- if boot from U disk
	if (Cfg.reco_U or Cfg.reco_N) and Cfg.whole_recover then
		-- only recover from U disk and whole recover need to do partitions 
		Cfg.new_partition = true	
	end
	
	if Cfg.new_partition then
		-- do partition and format action
		print("\n================ Make New Partitions =================")
		printMsg("开始分区……")
		ret = do_cmd { sfdisk_prefix..sfarg }
		if not ret then
			print("Error! Hard disk can not be divided.")
			printMsg("出错，磁盘无法分区！")
			return -1
		end
		printMsg("分区完成。")
	end
	
	-- whether do really format depends on the second element in each table of faction
	if Cfg.new_format then
		print("\n==================== Do Format =====================")
		printMsg("开始格式化……")
		for i, v in pairs(faction) do
			if v[2] then 
				io.write('--> '..v[1].." ... "); io.flush()
				if Cfg.verbose then
					ret = do_cmd { v[1] }
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
		end
		printMsg("格式化完成。")
	end
	
	-- mount essential partitions to localdir
	-- mount root fs
	for i, v in ipairs(par) do
		if v[MPNUM] == '/' then
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
				local mountP = function ()
					local dir = localdir..subdir
					lfs.mkdir(dir)
					-- mount other partitions
					ret = do_cmd { "mount "..localdisk..i.." "..dir }
					if not ret then print("mount other partitions failed."); printMsg("挂载其它分区失败！"); return -1 end
				end
				
				-- if whole recover, we will mount all partitions
				if Cfg.whole_recover then
					mountP()
				-- if system recover, we will not mount user partition
				elseif Cfg.system_recover and subdir ~= '/home' then
					mountP()
				-- if user recover, we will only mount user partition 	
				elseif Cfg.user_recover and subdir == '/home' then
					mountP()				
				end			
			end
		end	
	end	

	-- create backup directory
	local tmp_dir = localdir..backup
	ret = lfs.mkdir(tmp_dir)
	-- if not ret then print("make tmp dir failed."); printMsg("创建备份目录失败！"); return -1 end
	if par['Backup'] then
		local backupdev = localdisk..par['Backup']
		-- ATTENTION: 
		-- if recover from local disk, if /dev/hda2 has been mounted before,
		-- /dev/hda2 will now have been mounted for twice, to /root/ldisk and /mnt/backup
		ret = do_cmd { "mount "..backupdev.." "..tmp_dir }
		if not ret then 
			print("mount backup device failed. oh...");
			return -1
		end
	end
	-- mount tmpfs
	do_cmd { "mount none -t tmpfs /tmp" }
	
	-- if user recover, we should backup the original /home partition
	-- to /mnt/backup/home_backup_tmp.tar.gz firstly
	if Cfg.user_recover then
		
		print("Before user data recovery, we create a temporary backup package.")
		printMsg("在用户数据还原开始之前，我们创建一个临时备份包……")
		lfs.chdir(localdir)
		ret = do_cmd { "tar czf "..tmp_dir.."home_backup_tmp.tar.gz home" }
		if not ret then 
			print("Backup original home directory failed.")
			printMsg("备份用户目录失败。")
			return -1
		end
		lfs.chdir('-')
		
		ret = do_cmd { "umount "..localdir.."/home" }
		if not ret then 
			print("Umount home partition failed.")
			printMsg("卸载用户分区失败。")
			return -1
		end
		print("next step, format the user partition.")
		printMsg("格式化用户分区……")
		ret = do_cmd { "mkfs.ext3 "..localdisk..home_i..HO }
		if not ret then 
			print("Format home partition failed.")
			printMsg("格式化用户分区失败。")
			return -1
		end
		ret = do_cmd { "mount "..localdisk..home_i.." "..localdir.."/home" }
		if not ret then 
			print("Mount home partition failed.")
			printMsg("挂载用户分区失败。")
			return -1
		end
		
	end

	lfs.chdir(tmp_dir)
	-- delete files on backup partition
	if (Cfg.reco_U or Cfg.reco_N) and Cfg.system_recover then
		for file in lfs.dir(".") do
			if file == '.'
			or file == '..'
			or file == home_backup
			then
				-- nothing 
			else
				do_cmd { "rm -rf "..file }
			end
		end
	end
	lfs.chdir('-')
	
	-- if recover from U disk, and is not in user recover mode, do copying files here
	if Cfg.reco_U and (Cfg.whole_recover or Cfg.system_recover) then
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
		printMsg("系统文件拷贝完成。")
	
		local osfab = Cfg.OSFAB_NAME or "OSFab.img"
		if Cfg.OSFAB_NAME and Cfg.OSFAB_NAME ~= "" and lfs.attributes(udisk_dir..osfab) then
			print("Copy osfab file.")
			printMsg("拷贝组件映像文件到磁盘……")
			lfs.chdir( udisk_dir )
			ret = do_cmd { "bar -c 'cat > "..tmp_dir.."${bar_file}' "..osfab }
			if not ret then
				print("copy osfab failed.")
				printMsg("拷贝组件映像文件失败！")
				return -1
			end
			printMsg("组件映像文件拷贝完成。")
		end
		
		-- copy vmlinux, config.txt, boot.cfg and other files to disk
		do_cmd { "cp -a vmlinux "..tmp_dir }
		do_cmd { "cp -a vmlinuz "..tmp_dir }
		do_cmd { "cp -a font.ttf "..tmp_dir }
		do_cmd { "cp -a config.txt "..tmp_dir }
		do_cmd { "cp -a boot.cfg "..tmp_dir }
		do_cmd { "cp -a /root/os_config.txt "..tmp_dir }
		if Cfg.check1 then 
			do_cmd { "cp -a md5sum.txt "..tmp_dir }
		end
		do_cmd { "sync" }
		lfs.chdir( "-" )
	end
	
	if Cfg.reco_U then
		lfs.chdir("/")
		-- Umount the usb disk.
		ret = do_cmd { "umount "..udisk_dir }
		if not ret then
			print("Umount USB disk failed.")
		else
			print("**You can take off the USB disk**")
			printMsg("**现在可以拨出U盘了**")
		end
	end

	-- stuff recover from network
	if Cfg.reco_N and (Cfg.whole_recover or Cfg.system_recover) then
		-- search ethernet device, and open it
		local content = GetCMDOutput( "ifconfig -a" )
		local ethdev = content:match("eth[%w_]+")
		if not ethdev then
			print("Can't find ethernet device.")
			return -1		
		end
		ret = do_cmd { "ifconfig "..ethdev.." up " }
		if not ret then
			print("Can't open ethernet device.")
			return -1
		end
		-- get and set local IP
		local iplocal = "172.16.18.100" -- temporary
		
		do_cmd { "ifconfig "..ethdev.." "..iplocal }
		
		ret = lfs.chdir(tmp_dir)
		if not ret then 
			print("change directory to tmp_dir failed.")
			printMsg("切换到备份目录失败！")
			return -1 
		end
		-- down files from server IP and default direcotry
		-- base
		local server = Cfg.SERVER_IP or "192.168.1.100"
		
		-- down system files
		for i, v in pairs(files) do
			local basefile = v[1]
			local urlstr = "http://"..server.."/OSes/"..basefile;
			
			ret = do_cmd { "axel_daogang -n 1 "..urlstr }
			if not ret then
				print("Down file "..basefile.." failed.")
				return -1
			end
		end

		-- down component files
		if Cfg.OSFAB_NAME and Cfg.OSFAB_NAME ~= "" then
			local comfile = Cfg.OSFAB_NAME
			urlstr = "http://"..server.."/OSFab/"..comfile;
			ret = do_cmd { "axel_daogang -n 1 "..urlstr }
			if not ret then
				print("Down file "..comfile.." failed.")
				return -1
			end
		end

		local other_files = {
			"vmlinux",
			"vmlinuz",
			"font.ttf",
			"config.txt",
			"boot.cfg",
		}
		-- down other files
		for i, v in pairs(other_files) do
			local basefile = v
			local urlstr = "http://"..server.."/OSes/"..basefile;
			
			ret = do_cmd { "axel_daogang -n 1 "..urlstr }
			--[[ -- we don't check the correction of result
			if not ret then
				print("Down file "..basefile.." failed.")
				return -1
			end
			--]]
		end
	
		-- restore original system os_config.txt 
		do_cmd { "cp -a /root/os_config.txt "..tmp_dir }

	end

	-- change directory
	ret = lfs.chdir(tmp_dir)
	if not ret then print("change directory to tmp_dir failed."); printMsg("切换到备份目录失败！"); return -1 end
	-- remove the autostart.txt file, to prevent autostart next time
	do_cmd { "rm autostart.txt" }
	
	-- calculate actual md5sum value, now files are all in local disk
	if Cfg.check2 then
		if #md5sum_t > 0 then
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
	end
	
	-- extract
	print("\n=================== Extract Files ==================")
	printMsg("解压文件……")
	for i, v in pairs( files ) do
		local dir = v[2]
		-- handle the case of user recovery: home_backup.tar.gz
		if v[1]:match("home_backup") then
			dir = localdir
		end
		-- as long as flag is true, it extracts
		if v[3] then
			print("\n--> tar xzf "..v[1].." -C "..dir)
			if Cfg.verbose then
				ret = do_cmd { "tar xzvf "..v[1].." -C "..dir }
			else
				ret = do_cmd { "bar "..v[1].." | tar xzf - -C "..dir }		
			end
			if not ret then 
				-- auto repair mechanism
				if Cfg.user_recover then
					do_cmd { "rm -rf "..localdir.."/home/*" }
					do_cmd { "tar xf home_backup_tmp.tar.gz -C "..localdir }
					do_cmd { "sync" }
				end
				
				print("tar error."); 
				printMsg("解压出错！"); 
				return -1 
			end
		end
	end	

	do_cmd { "sync" }
	printMsg("文件解压完成。")
	print("")
	
	-- mount proc fs
	do_cmd { "mount none -t proc "..localdir.."/proc" }
	
	-- generate fstab
	print("Next we generate fstab file.")
	local fd = io.open(localdir.."/etc/fstab", "w")
	if not fd then
		print("Error! Can't open etc/fstab.")
		return -1
	end
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
		fd:write("title "..(bc.title or "Lemote System").." "..(bc.ver or "1.0.0")..'\n')
		local ch = string.char(string.byte('a') + root_i - 1)
		fd:write("\tkernel /dev/fs/ext2@wd0"..ch.."/boot/vmlinux\n")
		fd:write("\targs console=tty no_auto_cmd quiet root=/dev/hda"..(root_i or 1).." machtype="..(bc.machtype or "yeeloong").." "..(bc.res or ""))
		fd:close()
	end
	
	do_cmd { "sync" }	
	print("======================= Main Body End ========================")
	
	-- clean, dangerous!
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
	
	for i, v in ipairs(par) do
		if v[MPNUM] == '/' then	root_i = i end
		if v[MPNUM] == '/home' then home_i = i end
	end
	-- we must consider the partition of /home is the same to /
	if home_i == 0 then home_i = root_i end
	
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
		
		-- if we boot from local disk, we won't format the second partition
		if Cfg.reco_D and i == par.Backup then
			Cfg.format_table[i][2] = false	
		end
		-- if we use system recovery mode, we won't format the /home partition
		if Cfg.system_recover and (i == home_i or i == par.Backup) then
			Cfg.format_table[i][2] = false
		end
		-- if we use user recovery mode, we only format the /home partition
		--if Cfg.user_recover and i ~= home_i then
		--	Cfg.format_table[i][2] = false
		--end
		-- we should't format any partition when in user recover mode,
		-- as to /home partition, we should first backup it, then do format
		if Cfg.user_recover and Cfg.format_table[i] then
			Cfg.new_format = false
			Cfg.format_table[i][2] = false
		end
		
		--[[-- if in user recovery mode, and adopt the rm method, we won't format any partition, default commented
		if Cfg.user_recover then
			Cfg.format_table[i][2] = false
		end
		--]]
	end
	
	-- next we will form files_table: have three columns, 
	-- we should use some method to determine what package will be extracted
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
				-- acoording to current status to determin how many packages should be extracted
				-- these two mode need extract the base system package and the components package
				if Cfg.whole_recover or Cfg.system_recover then
					Cfg.files_table[file_count][3] = true
				-- user_recover only extract home_backup.tar.gz to /home
				elseif Cfg.user_recover then
					Cfg.files_table[file_count][3] = false
				end
			end		
		end
	end

	-- check the existance of other useful files in /root/ldisk
	-- if /dev/hda2 is not mounted on /root/ldisk, mount it 
	-- if recover from local disk, partition 2 has been mounted to /root/ldisk 
	-- first 'home_backup.tar.gz'
	if Cfg.user_recover then
		local content = GetCMDOutput( "mount" )
		if not content:match("/root/ldisk") then
			ret = do_cmd { "mount "..localdisk..par.Backup.." "..ldisk_dir }
			if not ret then 
				print("Mount backup partition failed.")
				printMsg("挂载备份分区失败。")
				return -1
			end
		end

		local file = ldisk_dir..home_backup
		if lfs.attributes(file) then
			file_count = file_count + 1
			Cfg.files_table[file_count] = {}
			Cfg.files_table[file_count][1] = home_backup
			Cfg.files_table[file_count][2] = localdir..'/home/'
			Cfg.files_table[file_count][3] = true
		end
		
		ret = do_cmd { "umount "..ldisk_dir }
		if not ret then
			print("Umount backup partition failed.")
			printMsg("卸载备份分区失败。")
			return -1
		end
	end
	-- more other files
	--
	--
	--
	
	
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
			sysver = Cfg.SYSTEM_NUM or "1.0.0"
			machtype = content:match("machtype=([%w_%-]+)")
			res = content:match("video=[%a%:]*%d+[xX]%d+%-%d%d%@%d%d")
			Cfg.default_bootcfg = {}
			Cfg.default_bootcfg.title = title
			Cfg.default_bootcfg.ver = sysver
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

function InstallComponents()
	-- now, we define in the case of whole and system recover, it needs to install components
	if Cfg.whole_recover or Cfg.system_recover then
		-- action for OSFab image
		local osfab = Cfg.OSFAB_NAME
		local machine = Cfg.default_bootcfg.machtype
		local version = Cfg.SYSTEM_VERSION
		local resolution = Cfg.default_bootcfg.res
		local backup_dir = localdir..backup
		local fabdir = "/osfab"

		if osfab and osfab ~= "" and lfs.attributes(backup_dir..osfab) then
			print("Next we will install some components, please wait by patience...")
			printMsg("下面安装组件，可能需要几分钟，请耐心等待。")
		
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
		end
	end

	return 0
end


function backupHomeDirectory()
	-- first time, backup the home data to /backup
	if (Cfg.reco_U or Cfg.reco_N) and Cfg.whole_recover then
		local tmp_dir = localdir..backup
		-- backup /mnt/home	
		lfs.chdir(localdir)
		ret = do_cmd { "tar czf "..tmp_dir..home_backup.." home" }
		if not ret then
			print("Warning! Backup home user data failed.")
		end
		lfs.chdir('-')
	end
end


--===================================================================
-- START
--===================================================================
-- mt.sleep(10)
do_cmd { "date -s 20121221" }
do_cmd { "setterm -blank 0" }

PrintHead()

-- find the size of local disk
local fdisk_output = GetCMDOutput( "fdisk -l" )
local real_disksize, unit = fdisk_output:match(": ([%d%.]+) ([GM])B,")
real_disksize = tonumber(real_disksize)
-- convert megabytes to gigabytes
if unit == 'M' then
	real_disksize = real_disksize / 1024;
end

-- script self containing
if not printMsg then
	printMsg = print
end

-- ensure Cfg have values
if not Cfg then
	print("Can't load global configuration, please check this file: config.txt.")
	printMsg("无法找到全局配置变量！请检查config.txt文件。")
	return -1
end

-- here, need to judge where the vmlinuz boot from
-- we use mounted information to distinguish
if Cfg.reco_N then
	Cfg.reco_U = false
	Cfg.reco_D = false
	
	if Cfg.user_recover then
		Cfg.whole_recover = true
		Cfg.system_recover = false
		Cfg.user_recover = false
	end

else
	local content = GetCMDOutput( "mount" )
	if content:match("/root/udisk") then
		Cfg.reco_U = true
	elseif content:match("/root/ldisk") then
		Cfg.reco_D = true
	else 
		Cfg.reco_N = true
		Cfg.whole_recover = true
		Cfg.system_recover = false
		Cfg.user_recover = false
	end

end

-- if external disksize is smaller than internal disksize, go ahead normally
if Cfg.disksize <= real_disksize then
	-- after this function, the config table has been transformed as the internal expresstion
	-- Cfg.default_partitions
	-- Cfg.sfdisk_arg
	-- Cfg.format_table
	-- Cfg.files_table
	collect_info()		
else
	print("The disk size of machine is too small.")
	printMsg("配置文件中指定的磁盘大小过大（大于实际磁盘容量）！请修改此参数。")
	return -1
end

-- backup the os_config.txt from the backup partition to /root
if (Cfg.reco_U or Cfg.reco_N) and (Cfg.whole_recover or Cfg.system_recover) then
	local num = Cfg.default_partitions.Backup
	do_cmd { "mount "..localdisk..num.." /mnt/" }
	do_cmd { "cp /mnt/os_config.txt /root/" }
	do_cmd { "umount /mnt" }
end	

-- WRONG: Recover backup partition from disk will not do partition action
-- if we don't umount backup partition, it will fail in later mount action.
-- if Cfg.reco_D then
	local content = GetCMDOutput( "mount" )
	if content:match("/root/ldisk") then
		ret = do_cmd { "umount "..ldisk_dir }
		if not ret then
			print("Umount backup partition failed.")
			printMsg("卸载备份分区失败。")
			return -1
		end
	end
-- end	

--
-- before recovery, we want a memory test
--
if Cfg.premem then
	print("\n--> Pre Memory Test")
	ret = do_cmd { "memtester_little 960 1" }
	if not ret then print("Memory test is failed. Error!"); return -1 end
end

-- check files' md5sum on U disk
if Cfg.check1 and Cfg.reco_U then
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

-- Main Work
local ret = Recover()
if ret ~= 0 then print("Error when recover."); return -1 end

ret = InstallComponents()
if ret ~= 0 then print("Error when install components."); return -1 end

backupHomeDirectory()

PrintBigPass()
return 0
-- do_cmd { "reboot" }
--==================================================================
-- END
--==================================================================

