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
	
	reco_U = false,
	reco_D = false,
	reco_L = false,
	
	whole_recover = true,
	system_recover = false,
	user_recover = false,
	
	new_partition = false,
	
	disksize = 60,
	premem = false,
	check1 = true,
	check2 = true,
	verbose = false,
	clean = false,
	
	sfdisk_arg = [[]],
	format_table = {},
	files_table = {},
	
}

