require 'json'
require 'open3'
require 'tempfile'

def run_osa_script(script)
  temp_file = Tempfile.new(['script', '.scpt'])
  temp_file.write(script)
  temp_file.close

  stdout, stderr, status = Open3.capture3("osascript #{temp_file.path}")

  temp_file.unlink

  unless status.success?
    puts "Error executing AppleScript: #{stderr}"
    exit 1
  end

  # logはstderrに出力される
  stderr
end

window_log = run_osa_script(<<~'OSA')
  tell application "Finder"
      set windowList to every window
      repeat with currentWindow in windowList
        set windowName to name of currentWindow
        set windowBounds to bounds of currentWindow
        set windowId to id of currentWindow
        try
          set windowPath to POSIX path of (target of currentWindow as alias)
          log "{\"window_id\": " & windowId & ", \"window_name\": \"" & windowName & "\", \"window_path\": \"" & windowPath & "\"}"
        on error
          # ウィンドウのパスが取得できない場合のエラーハンドリング。無視する
        end try
      end repeat
    end tell
  OSA

# https://www.macscripter.net/t/the-definitive-guide-to-screen-resolution-for-macos-ventura-13/74865/6
display_info = run_osa_script(<<~OSA)
use framework "AppKit"
use framework "Foundation"
use scripting additions

set visibleDisplayPositionSize to getVisibleDisplayPositionSize()

log visibleDisplayPositionSize

on getVisibleDisplayPositionSize()
	set theScreen to current application's NSScreen's mainScreen()
	set {{x1, y1}, {w1, h1}} to theScreen's frame()
	set {{x2, y2}, {w2, h2}} to theScreen's visibleFrame()
	return {x2 as integer,(h1 - h2 - y2) as integer,w2 as integer,h2 as integer}
end getVisibleDisplayPositionSize
OSA

puts "displayinfo"
puts display_info
_, _, w, h =  display_info.strip.split(",").map(&:strip).map(&:to_i)

windows = window_log.split("\n").map do |line|
  JSON.parse(line)
end
puts "windows"
puts windows

result_right = [] # [ window_id, x, y, w, h, path ]
result_left = []

windows = windows.sort_by do |window|
  [window["window_path"].start_with?("/Volumes/") ? 0 : 1, window["window_path"]]
end

mounted_drives = Dir.glob("/Volumes/*").select { |path| File.directory?(path) && !path.end_with?("Macintosh HD") }
mounted_drives.reject! { |path| path.include?("TimeMachine.localsnapshots") || path.include?("Installer") || path.include?("バックアップ") || path.include?("ykpythemind-mbp") || path.include?("mac studio") }
mounted_drives.reject! { |path| windows.any? { |window| window["window_path"].delete_suffix("/") == path } }
puts "mounted_drives"
puts mounted_drives

mounted_drives.each_with_index do |mounted_drive, index|
  windows.unshift({ "window_id" => :mounted_drive, "window_path" => mounted_drive })
  break if index == 1 # max 2
end

home_finder_exists = windows.any? { |window| window["window_path"].delete_suffix("/") == ENV["HOME"] }
unless home_finder_exists
  puts "Home Finder is not running"
  windows.unshift({ "window_id" => :finder })
end

windows.each_with_index do |window, index|
  window_id = window["window_id"] || :finder

  # 整理して出すのは4つまでが限界とする
  case index
  when 0
    result_left << [window_id, 0, 0, w / 2, h / 2, window["window_path"]]
  when 1
    result_left << [window_id, 0, h / 2, w / 2, h, window["window_path"]]
  when 2
    result_right << [window_id, w / 2, 0, w, h / 2, window["window_path"]]
  when 3
    result_right << [window_id, w / 2, h / 2, w, h, window["window_path"]]
  when 4..windows.size
    diff = 40 * (index - 3)
    result_right << [window_id, w / 2 , h / 2 + diff + 50, (w * 0.8).to_i, (h * 0.8).to_i, window["window_path"]]
  end
end

def process_bounds(bounds)
  pad = 40
  [bounds[0] + pad, bounds[1] + pad, bounds[2] - pad, bounds[3] - pad].join(", ")
end

def resize_window(window_id, bounds = [100, 100, 900, 700], path = nil)
  if window_id == :mounted_drive
    system(<<~OSA)
      osascript -e 'tell application "Finder"
        activate
        set targetWindow to make new Finder window
        set target of targetWindow to POSIX file "#{path}"
        set bounds of targetWindow to {#{process_bounds(bounds)}}
      end tell'
    OSA
    return
  end

  if window_id == :finder
    system(<<~OSA)
      osascript -e 'tell application "Finder"
        activate
        set targetWindow to make new Finder window
        set target of targetWindow to (path to home folder)
        set bounds of targetWindow to {#{process_bounds(bounds)}}
      end tell'
    OSA
    return
  end

  system(<<~OSA)
    osascript -e 'tell application "Finder"
      set targetWindow to (window id #{window_id})
      set bounds of targetWindow to {#{process_bounds(bounds)}}
    end tell'
  OSA
end

puts "left"
puts result_left
puts "right"
puts result_right

[*result_left, *result_right].each do |window|
  resize_window(window[0], window[1..4], window[5])
end

run_osa_script(<<~OSA)
  tell application "Finder" to activate
OSA
