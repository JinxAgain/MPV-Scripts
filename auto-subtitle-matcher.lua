-- Auto subtitle loader
-- This script automatically loads matching subtitles from sub-file-paths and video directory
-- Version 1.0.2

local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- 调试模式，设置为true将输出更多信息
local debug_mode = false

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
    -- Match pattern: name.S01E01; name S01E01
    local name, season, episode = filename:match("(.+)[%.%s]S(%d%d)E(%d%d)[%.%s]")

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
        
        -- TV show match: name, season, and episode must match
        if v_name and s_name and v_name:lower() == s_name:lower() and 
           v_season == s_season and v_episode == s_episode then
            return true
        end
    else
        -- It's a movie
        local v_name, v_year = extract_movie_info(video_file)
        local s_name, s_year = extract_movie_info(sub_file)

        msg.info("debug v_name = " .. v_name .. " s_name = " .. s_name)
        msg.info("debug v_year = " .. v_year .. " s_year = " .. s_year)
        
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
    
    local video_dir, video_filename = utils.split_path(video_path)
    
    -- 记录找到的字幕数量
    local subtitles_found = 0
    
    -- 1. 首先检查视频所在文件夹
    if debug_mode then
        msg.info("Scanning video directory for subtitles: " .. video_dir)
    end
    
    subtitles_found = scan_directory_for_subtitles(video_dir, video_filename, subtitles_found)
    
    -- 2. 然后检查sub-file-paths中指定的文件夹
    -- Get the subtitle directory from mpv's sub-file-paths setting
    local sub_paths_str = mp.get_property("sub-file-paths", "")
    if debug_mode then
        msg.info("Sub file paths setting: " .. sub_paths_str)
    end
    
    local sub_paths = {}
    
    -- 如果为空，默认使用'sub'目录
    if sub_paths_str == "" then
        local default_sub_dir = utils.join_path(video_dir, "sub")
        if default_sub_dir ~= video_dir then  -- 避免重复扫描视频目录
            table.insert(sub_paths, default_sub_dir)
            if debug_mode then
                msg.info("Using default 'sub' directory")
            end
        end
    else
        -- Parse the sub-file-paths using the new split function
        local paths = split_paths(sub_paths_str)
        for _, path in ipairs(paths) do
            if debug_mode then
                msg.info("Processing path: " .. path)
            end
            
            if path:match("^[A-Z]:[/\\]") or path:sub(1, 1) == "/" then
                -- Absolute path (Windows or Unix)
                table.insert(sub_paths, path)
                if debug_mode then
                    msg.info("Added absolute path: " .. path)
                end
            else
                -- Relative path
                local full_path = utils.join_path(video_dir, path)
                -- 避免重复扫描视频目录
                if full_path ~= video_dir then
                    table.insert(sub_paths, full_path)
                    if debug_mode then
                        msg.info("Added relative path: " .. full_path)
                    end
                end
            end
        end
    end
    
    -- Find all subtitle files in the directories and check for matches
    for _, sub_dir in ipairs(sub_paths) do
        subtitles_found = scan_directory_for_subtitles(sub_dir, video_filename, subtitles_found)
    end
    
    if subtitles_found > 0 then
        msg.info("Loaded " .. subtitles_found .. " matching subtitle(s)")
    else
        msg.warn("No matching subtitles found")
    end
end

-- Register the script to run when a file is loaded
mp.register_event("file-loaded", load_matching_subtitles)

msg.info("Auto subtitle matcher loaded")