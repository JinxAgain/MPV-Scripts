-- Auto subtitle loader
-- This script automatically loads matching subtitles from sub-file-paths and video directory
-- Version 1.0.2

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- 调试模式，设置为true将输出更多信息
local debug_mode = false -- Enable debug mode for testing

-- Function to URL decode a string (basic implementation)
local function url_decode(str)
    if not str then return nil end
    str = string.gsub (str, "+", " ")
    str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
    -- Decode common URL encodings if needed, e.g., %2F for /
    -- str = string.gsub(str, "%%2F", "/") 
    return str
end

-- Clean up a movie name by removing non-English characters and cleaning up separators
local function clean_movie_name(name)
    if not name then return nil end

    -- Replace dots, underscores with spaces
    name = name:gsub("[%._]", " ")
    -- Remove multiple spaces
    name = name:gsub("%s+", " ")
    -- Remove content within square brackets (non-greedy)
    name = name:gsub("%[.-%]", "")
    -- Remove content within parentheses (non-greedy)
    name = name:gsub("%(.-%)", "")
    -- Trim leading/trailing spaces
    name = name:gsub("^%s*(.-)%s*$", "%1")

    -- Extract only English text (if present)
    local english_name = name:match("[A-Za-z%s%.%_]+")
    
    -- If we found English text, use it; otherwise use the original name
    if english_name and english_name:match("%S") then -- check if it contains non-whitespace
        name = english_name
    end
    
    return name
end

-- Function to extract movie name and year from filename
local function extract_movie_info(filename)
    if not filename then return nil, nil end
    if debug_mode then msg.info("Extracting movie info from: " .. filename) end
    -- Match pattern: name year; name.year; prefix name year
    local name, year = filename:match("(.+)[%.%s](%d%d%d%d)[%.%s]")

    if not name or not year then
        -- 尝试匹配 "name (year)" 格式 (如 "The Shrouds (2024)")
        name, year = filename:match("(.+)[%.%s]%((%d%d%d%d)%)")
    end

    if name and year then
        name = clean_movie_name(name)
        return name, year
    end
    return nil, nil
end

-- Function to extract TV show info (name, season, episode)
local function extract_tv_info(filename)
    if not filename then return nil, nil, nil end
    if debug_mode then msg.info("Extracting TV info from: " .. filename) end
    -- Match pattern: name.S01E01; name S01E01
    local name, season, episode = filename:match("(.+)[%.%s][sS](%d%d)[eE](%d%d)[%.%s]")

    if name and season and episode then
        name = clean_movie_name(name)
        return name, season, episode
    end
    return nil, nil, nil
end

-- Function to determine if file is a movie or TV show
local function is_tv_show(filename)
    local _, _, episode = extract_tv_info(filename)
    return episode ~= nil
end

-- Function to determine if two filenames match according to our rules
local function is_matching_pair(video_file, sub_file)
    -- Check if it's a TV show
    if is_tv_show(video_file) then
        local v_name, v_season, v_episode = extract_tv_info(video_file)
        local s_name, s_season, s_episode = extract_tv_info(sub_file)

        if debug_mode then
            msg.info("Comparing TV Show:")
            msg.info("  Video: Name=" .. (v_name or "nil") .. ", S=" .. (v_season or "nil") .. ", E=" .. (v_episode or "nil"))
            msg.info("  Sub:   Name=" .. (s_name or "nil") .. ", S=" .. (s_season or "nil") .. ", E=" .. (s_episode or "nil"))
        end
        
        -- TV show match: name, season, and episode must match
        if v_name and s_name and v_name:lower() == s_name:lower() and 
           v_season == s_season and v_episode == s_episode then
            return true
        end
    else
        -- It's a movie
        local v_name, v_year = extract_movie_info(video_file)
        local s_name, s_year = extract_movie_info(sub_file)

        if debug_mode then
            msg.info("Comparing Movie:")
            msg.info("  Video: Name=" .. (v_name or "nil") .. ", Year=" .. (v_year or "nil"))
            msg.info("  Sub:   Name=" .. (s_name or "nil") .. ", Year=" .. (s_year or "nil"))
        end
        
        -- Movie match: name and year must match
        if v_name and s_name and v_name:lower() == s_name:lower() and 
           v_year == s_year then
            return true
        end
    end
    
    return false
end

-- Function to split string by multiple possible delimiters
local function split_paths(str)
    local result = {}
    -- 支持逗号(,)和分号(;)作为分隔符
    for path in str:gmatch("[^,;]+") do
        -- 去除可能存在的前后空格
        path = path:gsub("^%s*(.-)%s*$", "%1")
        table.insert(result, path)
    end
    return result
end

-- Function to scan directory for matching subtitles
local function scan_directory_for_subtitles(dir_path, video_filename, subtitles_found)
    if debug_mode then
        msg.info("Checking directory: " .. dir_path)
    end
    
    -- 检查目录是否存在
    local dir_info = utils.file_info(dir_path)
    if not dir_info or not dir_info.is_dir then
        msg.warn("Directory does not exist or is not accessible: " .. dir_path)
        return subtitles_found
    end
    
    local files = utils.readdir(dir_path)
    if files then
        for _, file in ipairs(files) do
            -- Check if the file is a subtitle
            local sub_ext = file:match("%.([^%.]+)$")
            if sub_ext and (
                sub_ext:lower() == "srt" or
                sub_ext:lower() == "ass" or
                sub_ext:lower() == "ssa" or
                sub_ext:lower() == "sub"
            ) then
                if debug_mode then
                    msg.info("Checking subtitle file: " .. file)
                end
                
                -- Check if it matches our video file
                if is_matching_pair(video_filename, file) then
                    local sub_path = utils.join_path(dir_path, file)
                    msg.info("Loading matching subtitle: " .. sub_path)
                    mp.commandv("sub-add", sub_path)
                    subtitles_found = subtitles_found + 1
                end
            end
        end
    else
        msg.warn("Could not read directory: " .. dir_path)
    end
    
    return subtitles_found
end

-- Main function to find and load matching subtitles
local function load_matching_subtitles()
    -- Get the current video file path
    local video_path = mp.get_property("path")
    if not video_path then
        msg.warn("No video file currently playing")
        return
    end
    
    if debug_mode then
        msg.info("Processing video: " .. video_path)
    end
    
    local video_dir = nil
    local video_filename = nil
    local is_network_stream = false
    local mpv_config_dir = mp.command_native({"expand-path", "~~/"}) -- Get mpv config dir path

    -- Check if it's a network stream
    if video_path:match("^https?://") then
        is_network_stream = true
        msg.info("Detected network stream: " .. video_path)
        
        -- Special handling for shegu.net
        if video_path:match("shegu%.net") then
            local key5_encoded = video_path:match("KEY5=([^&]+)")
            if key5_encoded then
                video_filename = url_decode(key5_encoded)
                msg.info("Extracted filename from shegu.net KEY5: " .. video_filename)
            else
                msg.warn("Could not extract KEY5 from shegu.net URL")
                -- Fallback: try to get filename from the end of the path part
                video_filename = video_path:match(".*/([^/?]+)[?]?") 
            end
        else
            -- General network stream: try to get filename from the end of the path part
             video_filename = video_path:match(".*/([^/?]+)[?]?") 
        end

        if not video_filename then
             -- Fallback if filename extraction failed
             video_filename = video_path:match(".*/([^/]+)$")
             if video_filename then
                 video_filename = video_filename:match("([^?]+)") -- Remove query string if present
             end
        end

        if video_filename then
             video_filename = url_decode(video_filename) -- Decode potential URL encoding in filename
             msg.info("Extracted filename from network stream: " .. video_filename)
        else
             msg.warn("Could not extract filename from network stream URL: " .. video_path)
             return -- Cannot proceed without a filename
        end
        -- For network streams, video_dir remains nil
    else
        -- Local file
        video_dir, video_filename = utils.split_path(video_path)
        msg.info("Processing local file: " .. video_filename .. " in dir: " .. video_dir)
    end

    if not video_filename then
        msg.error("Failed to determine video filename.")
        return
    end
    
    -- 记录找到的字幕数量
    local subtitles_found = 0
    
    -- 1. 检查视频所在文件夹 (仅限本地文件)
    if not is_network_stream and video_dir then
        if debug_mode then
            msg.info("Scanning video directory for subtitles: " .. video_dir)
        end
        subtitles_found = scan_directory_for_subtitles(video_dir, video_filename, subtitles_found)
    elseif is_network_stream then
         if debug_mode then
            msg.info("Skipping video directory scan for network stream.")
         end
    end
    
    -- 2. 检查sub-file-paths中指定的文件夹
    -- Get the subtitle directory from mpv's sub-file-paths setting
    local sub_paths_str = mp.get_property("sub-file-paths", "")
    if debug_mode then
        msg.info("Sub file paths setting: " .. sub_paths_str)
    end
    
    local sub_paths = {}
    local base_dir_for_relative = is_network_stream and mpv_config_dir or video_dir

    -- 如果为空，默认使用'sub'目录 (相对于 base_dir_for_relative)
    if sub_paths_str == "" then
        if base_dir_for_relative then
            local default_sub_dir = utils.join_path(base_dir_for_relative, "sub")
            -- Avoid scanning video_dir again if it's the same as default_sub_dir (only for local files)
            if not is_network_stream and default_sub_dir == video_dir then
                 if debug_mode then msg.info("Default 'sub' directory is same as video directory, skipping.") end
            else
                 table.insert(sub_paths, default_sub_dir)
                 if debug_mode then msg.info("Using default 'sub' directory relative to " .. base_dir_for_relative .. ": " .. default_sub_dir) end
            end
        else
             if debug_mode then msg.warn("Cannot determine base directory for default 'sub' path.") end
        end
    else
        -- Parse the sub-file-paths using the new split function
        local paths = split_paths(sub_paths_str)
        for _, path in ipairs(paths) do
            if debug_mode then
                msg.info("Processing sub-file-path entry: " .. path)
            end
            
            -- Expand ~~ paths relative to mpv config dir
            if path:sub(1, 2) == "~~" then
                 path = utils.join_path(mpv_config_dir, path:sub(4)) -- Remove ~~ and leading / or \
                 if debug_mode then msg.info("Expanded ~~ path to: " .. path) end
                 table.insert(sub_paths, path)
            elseif path:match("^[A-Z]:[/\\]") or path:sub(1, 1) == "/" then
                -- Absolute path (Windows or Unix)
                table.insert(sub_paths, path)
                if debug_mode then
                    msg.info("Added absolute path: " .. path)
                end
            else
                -- Relative path (relative to base_dir_for_relative)
                if base_dir_for_relative then
                    local full_path = utils.join_path(base_dir_for_relative, path)
                    -- Avoid scanning video_dir again if it's the same (only for local files)
                    if not is_network_stream and full_path == video_dir then
                         if debug_mode then msg.info("Relative path resolves to video directory, skipping: " .. full_path) end
                    else
                         table.insert(sub_paths, full_path)
                         if debug_mode then msg.info("Added relative path (relative to " .. base_dir_for_relative .. "): " .. full_path) end
                    end
                else
                     if debug_mode then msg.warn("Cannot determine base directory for relative path: " .. path) end
                end
            end
        end
    end
    
    -- Find all subtitle files in the directories and check for matches
    if debug_mode then msg.info("Scanning specified subtitle paths...") end
    for _, sub_dir in ipairs(sub_paths) do
        -- Ensure we don't re-scan the video directory if it was already scanned
        if not is_network_stream and sub_dir == video_dir then
             if debug_mode then msg.info("Skipping re-scan of video directory: " .. sub_dir) end
        else
             subtitles_found = scan_directory_for_subtitles(sub_dir, video_filename, subtitles_found)
        end
    end
    
    if subtitles_found > 0 then
        msg.info("Loaded " .. subtitles_found .. " matching subtitle(s)")
    else
        msg.warn("No matching subtitles found in specified paths.")
    end
end

-- Register the script to run when a file is loaded
mp.register_event("file-loaded", load_matching_subtitles)

msg.info("Auto subtitle matcher loaded (v1.0.3 - Network Stream Support)")
