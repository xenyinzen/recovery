--
-- here is local config file
--

HO 	= " 1>/dev/null 2>&1"

Cfg = {
	format_types = {
		'ext2',
		'ext3',
		'extend',
		'swap',
	};
	
	
	disksize = 0,
	premem = false,
	check1 = false,
	check2 = false,
	verbose = false,
	clean = false,
	
	sfdisk_arg = [[]],
	format_table = {},
	files_table = {},
	
}

