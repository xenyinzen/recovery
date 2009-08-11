--
-- here is local config file
--
cfg = {
	clean_after_recovery = false;
	
	scheme_2G = {
		geometry_action = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
,2048,L
,1024,S
EOF
]],
		format_action = {
			[1] = "mkfs.ext3 /dev/hda1",
			[2] = "mkswap /dev/hda2",
			[3] = "swapon /dev/hda2",		
		},	
		
		system_files = {
			[1] = "root-2G.tar.gz",
		},
		
		dst_partition = {
			[1] = "hda1",
		},
		
		tmp_dir = "hda1/backup/",
		
		
	},

	scheme_120_160G = {
		geometry_action = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
,5120,L
,5120,L
,1024,S
,,E
,100,L
,35000,L
,40960,L
,,
EOF
]],
		format_action = {
			[1] = "mkfs.ext3 /dev/hda1",
			[2] = "mkfs.ext3 /dev/hda2",
			[3] = "mkswap /dev/hda3",
			[4] = "swapon /dev/hda3",
			[5] = "mkfs.ext3 /dev/hda5",		
			[6] = "mkfs.ext3 /dev/hda6",		
			[7] = "mkfs.ext3 /dev/hda7",		
			[8] = "mkfs.ext3 /dev/hda8",		
		},	
		
		system_files = {
			[1] = "root.tar.gz",
			[2] = "etc.tar.gz",
			[3] = "home.tar.gz",
			[4] = "var.tar.gz",
		},
		
		dst_partition = {
			[1] = "hda1",
			[2] = "hda5",
			[3] = "hda6",
			[4] = "hda6",
		},
		
		tmp_dir = "hda2/",
	}

}

----------------------------------------------------------------
-- Predefine
----------------------------------------------------------------
cfg.scheme_choice = cfg.scheme_2G





	