--
-- here is local config file
--

HO = " 1>/dev/null 2>&1"

cfg = {
	clean = false;
	
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
--			["fstab"] = "fstab-2G",
		},
		
		dst_partition = {
			[1] = "hda1",
			["etc_location"] = { "1", "/etc/" },
			["tmp_dir"] = "hda1",
		},
		
		tmp_dir = "hda1/backup/",
		
		
	},

	scheme_8G = {
		geometry_action = [[
sfdisk -uM /dev/hda 1>/dev/null 2>&1 <<EOF
,2048,L
,200,L
,1024,S
,,
EOF
]],
		format_action = {
			[1] = "mkfs.ext3 /dev/hda1",
			[2] = "mkfs.ext3 /dev/hda2",
			[3] = "mkswap /dev/hda3",
			[4] = "swapon /dev/hda3",
			[5] = "mkfs.ext3 /dev/hda4",
		},	
		
		system_files = {
			[1] = "root.tar.gz",
			[2] = "etc.tar.gz",
			[3] = "home.tar.gz",
			[4] = "var.tar.gz",
			["fstab"] = "fstab-8G",
		},
		
		dst_partition = {
			[1] = "hda1",
			[2] = "hda2",
			[3] = "hda4",
			[4] = "hda4",
			["etc_location"] = { "1 2", "/etc/ /" },
			["tmp_dir"] = "hda4",
		},
		
		tmp_dir = "hda4/backup/",
		
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
			["fstab"] = "fstab-120GUP",
		},
		
		dst_partition = {
			[1] = "hda1",
			[2] = "hda5",
			[3] = "hda6",
			[4] = "hda6",
			["etc_location"] = { "1 2", "/etc/ /" },
			["tmp_dir"] = "hda2",
		},
		
		tmp_dir = "hda2/",
	}

}

----------------------------------------------------------------
-- Predefine
----------------------------------------------------------------
cfg.scheme_choice = cfg.scheme_2G





	