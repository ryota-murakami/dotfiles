# =============================================================================
# mov2gif - Convert MOV Video to GIF
# =============================================================================
#
# DESCRIPTION:
#   Converts a MOV video file to an optimized GIF animation.
#   Perfect for creating GIFs from screen recordings for GitHub
#   READMEs, documentation, or bug reports.
#
# USAGE:
#   mov2gif <input.mov>
#
# ARGUMENTS:
#   input.mov - Path to the MOV file to convert
#
# OUTPUT:
#   Creates <input>.gif in the same directory and opens it in Chrome.
#
# CONVERSION SETTINGS:
#   - Max width: 650px (maintains aspect ratio)
#   - Frame rate: 20 fps
#   - Uses lanczos scaling for quality
#   - Optimized with ImageMagick for smaller file size
#
# DEPENDENCIES:
#   - ffmpeg (brew install ffmpeg)
#   - imagemagick (brew install imagemagick)
#   - Google Chrome (for preview)
#
# EXAMPLE:
#   # Record screen with macOS Screenshot (Cmd+Shift+5)
#   # This creates a .mov file
#
#   $ mov2gif ~/Desktop/Screen\ Recording.mov
#   output file: /Users/me/Desktop/Screen Recording.gif
#   # Opens GIF in Chrome for preview
#
# TIP:
#   For GitHub: Keep GIFs under 10MB. Reduce resolution or
#   frame rate in the function if needed.
#
# =============================================================================
function mov2gif
    set out (echo $argv | sed 's/\.mov$/\.gif/')
    set max_width "650"
    set frames_per_second "20"
    ffmpeg -i $argv -vf "scale=min(iw\,$max_width):-1" -r "$frames_per_second" -sws_flags lanczos -f image2pipe -vcodec ppm - \
    | convert -delay 5 -layers Optimize -loop 0 - "$out" &&
    echo (tput setaf 2)output file: $out(tput sgr 0) &&
    open -a Google\ Chrome $out
end
