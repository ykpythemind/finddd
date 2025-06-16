require 'json'
require 'open3'

def run_osa_script(script)
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

    return stderr
  end

  stdout, stderr, status = Open3.capture3(<<~OSA)
    osascript -e '#{script}'
  OSA

  unless status.success?
    puts "Error executing AppleScript: #{stderr}"
    exit 1
  end

  # logはstderrに出力されるので、それを返す
  return stderr
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

result_right = [] # [ window_id, x, y, w, h
result_left = []

home_finder_exists = windows.any? do |window|
  window_path = window["window_path"]
  window_path == "#{ENV["HOME"]}/"
end

idx = 0
unless home_finder_exists
  puts "Home Finder is not running"
  result_left << [:finder, 0, 0, w / 2, h / 2]
  idx += 1
end

# todo: mountされたディレクトリがあればそれを優先して表示

windows.sort_by { |window| window["window_path"] }.each_with_index do |window, index|
  break if index > 4

  window_path = window["window_path"]

  case idx
  when 0
    result_left << [window["window_id"], 0, 0, w / 2, h / 2]
  when 1
    result_left << [window["window_id"], 0, h / 2, w / 2, h]
  when 2
    result_right << [window["window_id"], w / 2, 0, w, h / 2]
  when 3
    result_right << [window["window_id"], w / 2, h / 2, w, h]
  end

  idx += 1
end

def process_bounds(bounds)
  pad = 20
  [bounds[0] + pad, bounds[1] + pad, bounds[2] - pad, bounds[3] - pad].join(", ")
end

def resize_window(window_id, bounds = [100, 100, 900, 700], index = 1)
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

[*result_left, *result_right].each_with_index do |window, index|
  resize_window(window[0], window[1..4], index + 1)
end

run_osa_script(<<~OSA)
  tell application "Finder" to activate
OSA
