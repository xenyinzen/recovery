
package.path = package.path.."?.lua;../?.lua;../lib/?.lua;../../../lib/?.lua;"
package.cpath = package.cpath.."?.so;../?.so;../lib/?.so;../../../lib/?.so;"

require "lfs"
require "mt"

-- expand $var and ${var} in string
-- ${var} can call Lua functions: ${string.rep(' ', 10)}
-- `$' can be screened with `\'
-- `...': args for $<number>
-- if `...' is just a one table -- take it as args
function expand(s, ...)
	local args = {...}
	args = #args == 1 and type(args[1]) == "table" and args[1] or args
	-- return true if there was an expansion
	local function DoExpand (iscode)
		local was = false
		local mask = iscode and "()%$(%b{})" or "()%$([%a%d_]*)"
		local drepl = iscode and "\\$" or "\\\\$"
		
		s = s:gsub(mask, function (pos, code)
			if s:sub(pos-1, pos-1) == "\\" then return "$"..code
			else 
				was = true
				local v, err
				if iscode then code = code:sub(2, -2)
				else 
					local n = tonumber(code)
					if n then v = args[n] end
				end
				if not v then
					v, err = loadstring("return "..code) 
					if not v then error(err) end
					v = v()
				end
				if v == nil then v = "" end
				v = tostring(v):gsub("%$", drepl)
				return v
			end
		end)
		if not (iscode or was) then s = s:gsub("\\%$", "$") end
		return was
	end

	repeat DoExpand(true) until not DoExpand(false)
	return s
end

function printe(...)
	print(expand(...))
end

-----------------------------------------------------------------------------
--[[
cmd = "dmesg > 11111.txt"
do_cmd {
        --cmd,			-- command string
                                -- 	or function containing some statements 
        function ()
                if 3 < 4 then return true else return false end  
        end,
        
	true,			-- a boolean, a number, or string, or table, or function
        exception,
        --{ exception, 10, 5 },		-- exception function with parameters
        success,
        --{ success, 1, 2, 3 }		-- normal function with parameters
        
}
--]]
function do_cmd( t )
        local cmd_t = t[1]
        local cri_t = t[2]
        local except_t = t[3]
        local normal_t = t[4]

        local command = nil
        local command_args = nil
        local criterion = nil
        local exception = nil
        local except_args = nil
	local normal = nil
        local normal_args = nil

--      print("enter do_cmd")
        
        ----------------------------------------------------------
        -- Parameter checks
        ----------------------------------------------------------
        -- parameter check: cmd
        if not cmd_t then
        	print("Should have at least one parameter: cmd.")
        	return -1  
        end
        
        -- parameter check: except_t
        if type(cmd_t) == "string" then
        	command = cmd_t
        elseif type(cmd_t) == "table" then
                command = cmd_t[1]
        	-- remove the function name, reserve the parameter table
        	command_args = cmd_t
        	table.remove(command_args, 1)
        elseif type(cmd_t) == "function" then
          	command = cmd_t
        else
                print("The exception parameter must be a function")
                print("or a table containing a function as its first parameter.")
                return -1
        end
        
        -- parameter check: cri_t
        if cri_t then
	if type(cri_t) == "table" then
		print("Can't pass parameter of table into this function.")
		return -1     
	elseif type(cri_t) == "boolean" or type(cri_t) == "number" or type(cri_t) == "string" then
		criterion = cri_t
	elseif type(cri_t) == "function" then
		criterion = cri_t()
		if type(criterion) == "table" then
			print("Can't pass parameter of table into this function.")
			return -1     
		elseif type(criterion) == "function" then
			print("Can't pass iteration of function into this function.")
			return -1     
		end
	end
        end
        
        if except_t then
        -- parameter check: except_t
        if type(except_t) == "table" then
                exception = except_t[1]
        	-- remove the function name, reserve the parameter table
        	except_args = except_t
        	table.remove(except_args, 1)
        elseif type(except_t) == "function" then
          	exception = except_t
        else        
                print("The exception parameter must be a function or a table containing a function as its first parameter.")
                return -1
        end
        end
	
	if normal_t then
	-- parameter check: normal_t
        if type(normal_t) == "table" then
                normal = normal_t[1]
        	-- remove the function name, reserve the parameter table
        	normal_args = normal_t
        	table.remove(normal_args, 1)
        elseif type(normal_t) == "function" then
          	normal = normal_t
        else        
                print("The normal parameter must be a function or a table containing a function as its first parameter..")
                return -1
        end
	end

        ----------------------------------------------------------
        -- Cmd body executation section --------------------------
        ----------------------------------------------------------
	-- execute the cmd string or function
        local ret = 0
        if command then
        if type(command) == "string" then
                ret = os.execute(command)
        elseif type(command) == "function" then
                if command_args then
                	ret = command( unpack(command_args))
                else
                	ret = command()
                end
        end
        end
      
        ----------------------------------------------------------
        -- Return value check section
        ----------------------------------------------------------
        -- equal or not equal mode
        if criterion and exception then
        	if ret ~= criterion then
			if except_args then 
				exception( unpack(except_args) )
			else
				exception()
			end
			return false
		else
			ret = 0
		end
        end
        
        if normal and type(normal) == "function" then
                if normal_args then
                	normal( unpack(normal_args) )
                else
                	normal()
                end
        end
        
--      print("leave do_cmd")
        if ret == 0 then
	        return true
	else
		return false
	end
end

------------------------------------------------------------------------
function logError(str)
	local fd = io.open(logs.errfile, "a")
	if not fd then
		fd = assert(io.open(logs.errfile, "w"))
	end
	fd:write(str..'\n')

	fd:close()
end

function logDetail(str)
	local fd = io.open(logs.err_details, "a")
	if fd ~= nil then
		fd:write(str..'\n')
	end
	fd:close()
end

function reportError( i_name )
	logError(error_db[i_name][1])
	logDetail(error_db[i_name][2])
	
	printError(error_db[i_name][1])
	printError(error_db[i_name][2])

end

-- Judge input
-- params = {
-- 	pattern = ,
--	str_prompt = ,
--	err_index = ,
--	err_prompt = ,
-- 	suc_prompt = ,
-- }
function doJudgement( params )
	-- pattern can be choosed in "YN", "YNR", and so on
	params.pattern = params.pattern or "YN"
	-- add this loop to filter the chars in the choice set but not neccessary to us
	while true do
		local key = judgement(params.str_prompt)

		if params.pattern == "YN" then
			-- yes
			if key == 121 then
				if params.suc_prompt then printMsg(params.suc_prompt) end
				return true
			-- no
			elseif key == 110 then
				if params.err_prompt then printMsg(params.err_prompt) end
				printMsg("record the error info to logfile.")
				reportError( params.err_index )
				return false
			end
		elseif params.pattern == "YNR" then
			-- Nothing now
		end
	end
end


----------------------------------------------------------------------
-- Device related functions
----------------------------------------------------------------------
function getEthDEV()
	fd = assert(io.open(con.NET_INFO_FILE, "r"))
	content = fd:read("*all")

	local ethdev = string.match(content, "eth%d+[_%w]*")
	if not ethdev then
		fd:close()
		return nil
	end

	fd:close()
	return ethdev
end


function getWDEV()
	fd = assert(io.open(con.NET_INFO_FILE, "r"))
	content = fd:read("*all")

	local wdev = string.match(content, "wlan%d+[_%w]*")
	if not wdev then
		fd:close()
		return nil
	end

	fd:close()
	return wdev
end

function getHexChars( len)
	if not len then return nil end
	
	if type( len) ~= "number" then
		len = tonumber( len)
	end
	
	if len < 1 then return nil end
	local str = nil
	while true do
		str = getNChars( len)
		if not string.match( str, "[g-zG-Z]") then break end
	end
	return 	str
end

function getNthStr( str, n)
        local l = 0
        for i = 1, n-1 do
                _, l = string.find( str, "%S+%s*", l+1)
                if not l then break end
        end
        
        if l then 
                _, _, data = string.find( str, "(%S+)%s*", l+1)
                return data
        end
end

function getBurninXY( str)
        local i, x, y = 0

        print( "mt_lib.lua str: " .. str)
        
        for i,v in ipairs( con.FLOW) do
                print( "mt_lib.lua i: " .. i .." v: " .. v)
                if v == str then
                        break     
                end
        end
        
        x = con.BURNIN_SPLIT_X * (i % con.BURNIN_SPLIT_X_NUM)
        y = con.BURNIN_SPLIT_Y_START + con.BURNIN_SPLIT_Y * math.floor( i / con.BURNIN_SPLIT_Y_NUM )
        print( "mt_lib.lua x " .. x .. " y " ..y)
        
        return x, y
end


