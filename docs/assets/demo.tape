# eco-commander demo recording
# Run: vhs docs/assets/demo.tape

Output docs/assets/demo.gif
Output docs/assets/demo.webm

Set Shell "zsh"
Set FontSize 15
Set Width 960
Set Height 540
Set Theme "Catppuccin Mocha"
Set Padding 20
Set TypingSpeed 40ms
Set PlaybackSpeed 0.5

# Title pause
Sleep 500ms

# Show ecosystem status
Type "eco status"
Sleep 300ms
Enter
Sleep 4s

# List available recipes
Type "eco list"
Sleep 300ms
Enter
Sleep 3s

# Show doctor check
Type "eco doctor"
Sleep 300ms
Enter
Sleep 3s

# Final pause
Sleep 1s
