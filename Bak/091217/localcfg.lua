--
-- here is local config file
--

HO 	= " 1>/dev/null 2>&1"

Cfg = {
	format_types = {
		'ext2',
		'ext3',
		'fat',
		'extend',
		'swap',
	};
	
	
	disksize = 0,
	premem = false,
	check1 = true,
	check2 = true,
	verbose = false,
	clean = false,
	boot_U = true,
	boot_D = true,
	boot_L = true,
	
	sfdisk_arg = [[]],
	format_table = {},
	files_table = {},
	
}

