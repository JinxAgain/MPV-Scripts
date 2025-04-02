-- shegu_filename_extractor.lua
-- This script extracts the correct video filename from shegu.net HTTP links

local utils = require 'mp.utils'

-- Function to extract the filename from KEY5 parameter
function extract_filename(url)
    -- Check if URL is from shegu.net domain
    if not string.match(url, "shegu%.net") then
        return nil
    end
    
    -- Try to extract the KEY5 parameter
    local key5 = string.match(url, "KEY5=([^&]+)")
    if key5 then
        -- URL decode the filename (replace %xx escapes with their characters)
        key5 = key5:gsub("%%(%x%x)", function(h)
            return string.char(tonumber(h, 16))
        end)
        -- Replace '+' with spaces if present
        key5 = key5:gsub("+", " ")
        return key5
    end
    
    return nil
end

-- Function to handle the file loaded event
function on_file_loaded()
    local path = mp.get_property("path")
    
    -- Check if the path is an HTTP URL
    if path and string.match(path, "^https?://") then
        local filename = extract_filename(path)
        
        if filename then
            -- Set the window title (the most visible title)
            mp.set_property("title", filename)
            
            -- Set the displayed media title in the OSD
            mp.set_property("force-media-title", filename)
            
            -- Set the internal media title
            mp.set_property("media-title", filename)
            
            -- Set the filename for saving
            mp.set_property("stream-open-filename", filename)
            
            -- Show a notification message
            mp.osd_message("Title set to: " .. filename)
            mp.msg.info("Title changed to: " .. filename)
        end
    end
end

-- Register the file loaded event
mp.register_event("file-loaded", on_file_loaded)