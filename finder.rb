require 'json'

system(<<~'OSA')
  osascript -e 'tell application "Finder"
    set windowList to every window
    repeat with currentWindow in windowList
      set windowName to name of currentWindow
      set windowBounds to bounds of currentWindow
      set windowId to id of currentWindow
      try
        set windowPath to POSIX path of (target of currentWindow as alias)
        log "Window ID: " & windowId & " - Window: " & windowName & " - Path: " & windowPath & " - Bounds: " & windowBounds
      on error
        log "Window ID: " & windowId & " - Window: " & windowName & " - Path: (unknown) - Bounds: " & windowBounds
      end try
    end repeat
  end tell'
OSA

# 特定のウィンドウをリサイズ
def resize_window(window_id, bounds = [100, 100, 900, 700])
  system(<<~OSA)
    osascript -e 'tell application "Finder"
      set targetWindow to window id #{window_id}
      set bounds of targetWindow to {#{bounds.join(', ')}}
    end tell'
  OSA
end

# 使用例:
#resize_window("4445", [100, 100, 100, 100])  # デフォルトサイズ(800x600)にリサイズ
# resize_window(12345, [100, 100, 1100, 900])  # カスタムサイズ(1000x800)にリサイズ
